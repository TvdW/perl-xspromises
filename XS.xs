#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#include <stdbool.h>

#define MY_CXT_KEY "Promise::XS::_guts" XS_VERSION

#define PROMISE_CLASS "Promise::XS"
#define PROMISE_CLASS_TYPE Promise__XS

#define DEFERRED_CLASS "Promise::XS::Deferred"
#define DEFERRED_CLASS_TYPE Promise__XS__Deferred

typedef struct xspr_callback_s xspr_callback_t;
typedef struct xspr_promise_s xspr_promise_t;
typedef struct xspr_result_s xspr_result_t;
typedef struct xspr_callback_queue_s xspr_callback_queue_t;

typedef enum {
    XSPR_STATE_NONE,
    XSPR_STATE_PENDING,
    XSPR_STATE_FINISHED,
} xspr_promise_state_t;

typedef enum {
    XSPR_RESULT_NONE,
    XSPR_RESULT_RESOLVED,
    XSPR_RESULT_REJECTED,
    XSPR_RESULT_BOTH
} xspr_result_state_t;

typedef enum {
    XSPR_CALLBACK_PERL,
    XSPR_CALLBACK_FINALLY,
    XSPR_CALLBACK_CHAIN
} xspr_callback_type_t;

struct xspr_callback_s {
    xspr_callback_type_t type;
    union {
        struct {
            SV* on_resolve;
            SV* on_reject;
            xspr_promise_t* next;
        } perl;
        struct {
            SV* on_finally;
            xspr_promise_t* next;
        } finally;
        xspr_promise_t* chain;
    };
};

struct xspr_result_s {
    xspr_result_state_t state;
    SV* result;
    int refs;
};

struct xspr_promise_s {
    bool detect_leak_yn;
    SV* unhandled_rejection_sv;
    xspr_promise_state_t state;
    int refs;
    union {
        struct {
            xspr_callback_t** callbacks;
            int callbacks_count;
        } pending;
        struct {
            xspr_result_t *result;
        } finished;
    };
};

struct xspr_callback_queue_s {
    xspr_promise_t* origin;
    xspr_callback_t* callback;
    xspr_callback_queue_t* next;
};

xspr_callback_t* xspr_callback_new_perl(pTHX_ SV* on_resolve, SV* on_reject, xspr_promise_t* next);
xspr_callback_t* xspr_callback_new_chain(pTHX_ xspr_promise_t* chain);
void xspr_callback_process(pTHX_ xspr_callback_t* callback, xspr_promise_t* origin);
void xspr_callback_free(pTHX_ xspr_callback_t* callback);

xspr_promise_t* xspr_promise_new(pTHX);
void xspr_promise_then(pTHX_ xspr_promise_t* promise, xspr_callback_t* callback);
void xspr_promise_finish(pTHX_ xspr_promise_t* promise, xspr_result_t *result);
void xspr_promise_incref(pTHX_ xspr_promise_t* promise);
void xspr_promise_decref(pTHX_ xspr_promise_t* promise);

xspr_result_t* xspr_result_new(pTHX_ xspr_result_state_t state);
xspr_result_t* xspr_result_from_error(pTHX_ const char *error);
void xspr_result_incref(pTHX_ xspr_result_t* result);
void xspr_result_decref(pTHX_ xspr_result_t* result);

xspr_result_t* xspr_invoke_perl(pTHX_ SV* perl_fn, SV* input);
xspr_promise_t* xspr_promise_from_sv(pTHX_ SV* input);


typedef struct {
    xspr_callback_queue_t* queue_head;
    xspr_callback_queue_t* queue_tail;
    int in_flush;
    int backend_scheduled;
    SV* conversion_helper;
} my_cxt_t;

typedef struct {
    xspr_promise_t* promise;
} DEFERRED_CLASS_TYPE;

typedef struct {
    xspr_promise_t* promise;
} PROMISE_CLASS_TYPE;

START_MY_CXT

/* Process a single callback */
void xspr_callback_process(pTHX_ xspr_callback_t* callback, xspr_promise_t* origin)
{
    assert(origin->state == XSPR_STATE_FINISHED);

    if (callback->type == XSPR_CALLBACK_CHAIN) {
        xspr_promise_finish(aTHX_ callback->chain, origin->finished.result);

    } else if (callback->type == XSPR_CALLBACK_PERL) {
        SV* callback_fn;

        if (origin->finished.result->state == XSPR_RESULT_RESOLVED) {
            callback_fn = callback->perl.on_resolve;
        } else if (origin->finished.result->state == XSPR_RESULT_REJECTED) {
            callback_fn = callback->perl.on_reject;

            // If we got a REJECTED callback, then we’re handling the rejection.
            // Even if not, though, we’re creating another promise, and that
            // promise will either handle the rejection or report non-handling.
            // So, in either case, we want to clear the unhandled rejection.
            origin->unhandled_rejection_sv = NULL;
        } else {
            callback_fn = NULL; /* Be quiet, bad compiler! */
            assert(0);
        }

        if (callback_fn != NULL) {
            xspr_result_t* result;
            result = xspr_invoke_perl(aTHX_
                                      callback_fn,
                                      origin->finished.result->result
                                      );

            if (callback->perl.next != NULL) {
                int skip_passthrough = 0;

                if (result->state == XSPR_RESULT_RESOLVED) {
                    xspr_promise_t* promise = xspr_promise_from_sv(aTHX_ result->result);
                    if (promise != NULL) {
                        if ( promise == callback->perl.next) {
                            /* This is an extreme corner case the A+ spec made us implement: we need to reject
                            * cases where the promise created from then() is passed back to its own callback */
                            xspr_result_t* chain_error = xspr_result_from_error(aTHX_ "TypeError");
                            xspr_promise_finish(aTHX_ callback->perl.next, chain_error);

                            xspr_result_decref(aTHX_ chain_error);
                        }
                        else {
//warn("Fairly normal case: we returned a promise from the callback\n");
                            /* Fairly normal case: we returned a promise from the callback */
                            xspr_callback_t* chainback = xspr_callback_new_chain(aTHX_ callback->perl.next);
                            xspr_promise_then(aTHX_ promise, chainback);
                            promise->unhandled_rejection_sv = NULL;
                        }

                        xspr_promise_decref(aTHX_ promise);
                        skip_passthrough = 1;
//warn("Fairly normal case: END\n");
                    }
                }

                if (!skip_passthrough) {
//warn("before promise finish from callback\n");
                    xspr_promise_finish(aTHX_ callback->perl.next, result);
//warn("after promise finish from callback\n");
                }
            }

//warn("before xspr_result_decref\n");
//sv_dump(result->result);
            xspr_result_decref(aTHX_ result);
//warn("after xspr_result_decref\n");

        } else if (callback->perl.next) {
            /* No callback, so we're just passing the result along. */
            xspr_result_t* result = origin->finished.result;
            xspr_promise_finish(aTHX_ callback->perl.next, result);
        }

    } else if (callback->type == XSPR_CALLBACK_FINALLY) {
        SV* callback_fn = callback->finally.on_finally;
        if (callback_fn != NULL) {
            xspr_result_t* result;
            result = xspr_invoke_perl(aTHX_
                                      callback_fn,
                                      origin->finished.result->result
                                      );
            xspr_result_decref(aTHX_ result);
        }

        if (callback->finally.next != NULL) {
            xspr_promise_finish(aTHX_ callback->finally.next, origin->finished.result);
        }

    } else {
        assert(0);
    }
}

/* Frees the xspr_callback_t structure */
void xspr_callback_free(pTHX_ xspr_callback_t *callback)
{
    if (callback->type == XSPR_CALLBACK_CHAIN) {
        xspr_promise_decref(aTHX_ callback->chain);

    } else if (callback->type == XSPR_CALLBACK_PERL) {
        SvREFCNT_dec(callback->perl.on_resolve);
        SvREFCNT_dec(callback->perl.on_reject);
        if (callback->perl.next != NULL)
            xspr_promise_decref(aTHX_ callback->perl.next);

    } else if (callback->type == XSPR_CALLBACK_FINALLY) {
        SvREFCNT_dec(callback->finally.on_finally);
        if (callback->finally.next != NULL)
            xspr_promise_decref(aTHX_ callback->finally.next);

    } else {
        assert(0);
    }

    Safefree(callback);
}

/* Invoke the user's perl code. We need to be really sure this doesn't return early via croak/next/etc. */
xspr_result_t* xspr_invoke_perl(pTHX_ SV* perl_fn, SV* input)
{
    dSP;
    int i;
    SV* error;
    xspr_result_t* result;

    if (!SvROK(perl_fn)) {
        return xspr_result_from_error(aTHX_ "promise callbacks need to be a CODE reference");
    }

    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    EXTEND(SP, 1);
    PUSHs(input);
    PUTBACK;

    /* Clear $_ so that callbacks don't end up talking to each other by accident */
    SAVE_DEFSV;
    DEFSV_set(sv_newmortal());

    call_sv(perl_fn, G_EVAL|G_SCALAR);

    SPAGAIN;
    error = ERRSV;
    if (SvTRUE(error)) {
        result = xspr_result_new(aTHX_ XSPR_RESULT_REJECTED);
        result->result = newSVsv(error);
    } else {
        result = xspr_result_new(aTHX_ XSPR_RESULT_RESOLVED);
        result->result = SvREFCNT_inc(POPs);
    }
    PUTBACK;

    FREETMPS;
    LEAVE;

    return result;
}

/* Increments the ref count for xspr_result_t */
void xspr_result_incref(pTHX_ xspr_result_t* result)
{
    result->refs++;
}

/* Decrements the ref count for the xspr_result_t, freeing the structure if needed */
void xspr_result_decref(pTHX_ xspr_result_t* result)
{
    if (--(result->refs) == 0) {
        SvREFCNT_dec(result->result);
        Safefree(result);
    }
}

void xspr_immediate_process(pTHX_ xspr_callback_t* callback, xspr_promise_t* promise)
{
    xspr_callback_process(aTHX_ callback, promise);

    /* Destroy the structure */
    xspr_callback_free(aTHX_ callback);
}

/* Transitions a promise from pending to finished, using the given result */
void xspr_promise_finish(pTHX_ xspr_promise_t* promise, xspr_result_t* result)
{
    assert(promise->state == XSPR_STATE_PENDING);
    xspr_callback_t** pending_callbacks = promise->pending.callbacks;
    int count = promise->pending.callbacks_count;

    if (count == 0 && result->state == XSPR_RESULT_REJECTED) {
        promise->unhandled_rejection_sv = result->result;
    }

    promise->state = XSPR_STATE_FINISHED;
    promise->finished.result = result;
    xspr_result_incref(aTHX_ promise->finished.result);

    int i;
    for (i = 0; i < count; i++) {
        xspr_immediate_process(aTHX_ pending_callbacks[i], promise);
    }
    Safefree(pending_callbacks);
}

/* Create a new xspr_result_t object with the given number of item slots */
xspr_result_t* xspr_result_new(pTHX_ xspr_result_state_t state)
{
    xspr_result_t* result;
    Newxz(result, 1, xspr_result_t);
    result->state = state;
    result->refs = 1;
    return result;
}

xspr_result_t* xspr_result_from_error(pTHX_ const char *error)
{
    xspr_result_t* result = xspr_result_new(aTHX_ XSPR_RESULT_REJECTED);
    result->result = newSVpv(error, 0);
    return result;
}

/* Increments the ref count for xspr_promise_t */
void xspr_promise_incref(pTHX_ xspr_promise_t* promise)
{
    (promise->refs)++;
}

/* Decrements the ref count for the xspr_promise_t, freeing the structure if needed */
void xspr_promise_decref(pTHX_ xspr_promise_t *promise)
{
    if (--(promise->refs) == 0) {
        if (promise->state == XSPR_STATE_PENDING) {
            /* XXX: is this a bad thing we should warn for? */
            int count = promise->pending.callbacks_count;
            xspr_callback_t **callbacks = promise->pending.callbacks;
            int i;
            for (i = 0; i < count; i++) {
                xspr_callback_free(aTHX_ callbacks[i]);
            }
            Safefree(callbacks);

        } else if (promise->state == XSPR_STATE_FINISHED) {
            xspr_result_decref(aTHX_ promise->finished.result);

        } else {
            assert(0);
        }

        Safefree(promise);
    }
}

/* Creates a new promise. It's that simple. */
xspr_promise_t* xspr_promise_new(pTHX)
{
    xspr_promise_t* promise;
    Newxz(promise, 1, xspr_promise_t);
    promise->refs = 1;
    promise->state = XSPR_STATE_PENDING;
    promise->unhandled_rejection_sv = NULL;
    return promise;
}

xspr_callback_t* xspr_callback_new_perl(pTHX_ SV* on_resolve, SV* on_reject, xspr_promise_t* next)
{
    xspr_callback_t* callback;
    Newxz(callback, 1, xspr_callback_t);
    callback->type = XSPR_CALLBACK_PERL;
    if (SvOK(on_resolve))
        callback->perl.on_resolve = newSVsv(on_resolve);
    if (SvOK(on_reject))
        callback->perl.on_reject = newSVsv(on_reject);
    callback->perl.next = next;
    if (next)
        xspr_promise_incref(aTHX_ callback->perl.next);
    return callback;
}

xspr_callback_t* xspr_callback_new_finally(pTHX_ SV* on_finally, xspr_promise_t* next)
{
    xspr_callback_t* callback;
    Newxz(callback, 1, xspr_callback_t);
    callback->type = XSPR_CALLBACK_FINALLY;
    if (SvOK(on_finally))
        callback->finally.on_finally = newSVsv(on_finally);
    callback->finally.next = next;
    if (next)
        xspr_promise_incref(aTHX_ callback->finally.next);
    return callback;
}

xspr_callback_t* xspr_callback_new_chain(pTHX_ xspr_promise_t* chain)
{
    xspr_callback_t* callback;
    Newxz(callback, 1, xspr_callback_t);
    callback->type = XSPR_CALLBACK_CHAIN;
    callback->chain = chain;
    xspr_promise_incref(aTHX_ chain);
    return callback;
}

/* Adds a then to the promise. Takes ownership of the callback */
void xspr_promise_then(pTHX_ xspr_promise_t* promise, xspr_callback_t* callback)
{
//warn("start xspr_promise_then\n");
    if (promise->state == XSPR_STATE_PENDING) {
        promise->pending.callbacks_count++;
        Renew(promise->pending.callbacks, promise->pending.callbacks_count, xspr_callback_t*);
        promise->pending.callbacks[promise->pending.callbacks_count-1] = callback;

    } else if (promise->state == XSPR_STATE_FINISHED) {
//fprintf(stderr, "then(): state == FINISHED\n");

        xspr_immediate_process(aTHX_ callback, promise);
    } else {
        assert(0);
    }
//warn("end xspr_promise_then\n");
}

/* Returns a promise if the given SV is a thenable. Ownership handed to the caller! */
xspr_promise_t* xspr_promise_from_sv(pTHX_ SV* input)
{
    if (input == NULL || !sv_isobject(input)) {
        return NULL;
    }

    /* If we got one of our own promises: great, not much to do here! */
    if (sv_derived_from(input, PROMISE_CLASS)) {
        IV tmp = SvIV((SV*)SvRV(input));
        PROMISE_CLASS_TYPE* promise = INT2PTR(PROMISE_CLASS_TYPE*, tmp);
        xspr_promise_incref(aTHX_ promise->promise);
        return promise->promise;
    }

    /* Maybe we got another type of promise. Let's convert it */
    GV* method_gv = gv_fetchmethod_autoload(SvSTASH(SvRV(input)), "then", FALSE);
    if (method_gv != NULL && isGV(method_gv) && GvCV(method_gv) != NULL) {
        dMY_CXT;

        xspr_result_t* new_result = xspr_invoke_perl(aTHX_ MY_CXT.conversion_helper, input);
        if (new_result->state == XSPR_RESULT_RESOLVED &&
            new_result->result != NULL &&
            SvROK(new_result->result) &&
            sv_derived_from(new_result->result, PROMISE_CLASS)) {
            /* This is expected: our conversion function returned us one of our own promises */
            IV tmp = SvIV((SV*)SvRV(new_result->result));
            PROMISE_CLASS_TYPE* new_promise = INT2PTR(PROMISE_CLASS_TYPE*, tmp);

            xspr_promise_t* promise = new_promise->promise;
            xspr_promise_incref(aTHX_ promise);

            xspr_result_decref(aTHX_ new_result);
printf("Got a different promise 1\n");
            return promise;

        } else {
            xspr_promise_t* promise = xspr_promise_new(aTHX);
            xspr_promise_finish(aTHX_ promise, new_result);
            xspr_result_decref(aTHX_ new_result);
printf("Got a different promise 2\n");
            return promise;
        }
    }

    /* We didn't get a promise. */
    return NULL;
}

Promise__XS__Deferred* _get_deferred_from_sv(pTHX_ SV *self_sv) {
    SV *referent = SvRV(self_sv);
    return (Promise__XS__Deferred *) SvUV(referent);
}

Promise__XS* _get_promise_from_sv(pTHX_ SV *self_sv) {
    SV *referent = SvRV(self_sv);
    return (Promise__XS *) SvUV(referent);
}

SV* _ptr_to_svrv(pTHX_ void* ptr, HV* stash) {
    SV* referent = newSVuv( (const UV)(ptr) );
    SV* retval = newRV_inc(referent);
    sv_bless(retval, stash);

    return retval;
}

HV *pxs_deferred_stash = NULL;
HV *pxs_stash = NULL;

//----------------------------------------------------------------------

MODULE = Promise::XS     PACKAGE = Promise::XS::Deferred

BOOT:
{
    /* XXX: do we need a CLONE? */

    MY_CXT_INIT;
    MY_CXT.queue_head = NULL;
    MY_CXT.queue_tail = NULL;
    MY_CXT.in_flush = 0;
    MY_CXT.backend_scheduled = 0;
    MY_CXT.conversion_helper = NULL;

    pxs_stash = gv_stashpv(PROMISE_CLASS, FALSE);
    pxs_deferred_stash = gv_stashpv(DEFERRED_CLASS, FALSE);
}

SV *
create()
    CODE:
        DEFERRED_CLASS_TYPE* deferred_ptr;
        Newxz(deferred_ptr, 1, DEFERRED_CLASS_TYPE);

        xspr_promise_t* promise = xspr_promise_new(aTHX);

        SV *detect_leak_perl = get_sv("Promise::XS::DETECT_MEMORY_LEAKS", 0);

        promise->detect_leak_yn = detect_leak_perl && SvTRUE(detect_leak_perl);

        deferred_ptr->promise = promise;

        RETVAL = _ptr_to_svrv(aTHX_ deferred_ptr, pxs_deferred_stash);
    OUTPUT:
        RETVAL

void
___set_conversion_helper(helper)
        SV* helper
    CODE:
        dMY_CXT;
        if (MY_CXT.conversion_helper != NULL)
            croak("Refusing to set a conversion helper twice");
        MY_CXT.conversion_helper = newSVsv(helper);

MODULE = Promise::XS     PACKAGE = Promise::XS::Deferred

SV*
promise(SV* self_sv)
    CODE:
        Promise__XS__Deferred* self = _get_deferred_from_sv(aTHX_ self_sv);

        Promise__XS* promise_ptr;
        Newxz(promise_ptr, 1, PROMISE_CLASS_TYPE);
        promise_ptr->promise = self->promise;
        xspr_promise_incref(aTHX_ promise_ptr->promise);

        RETVAL = _ptr_to_svrv(aTHX_ promise_ptr, pxs_stash);
    OUTPUT:
        RETVAL

void
resolve(SV *self_sv, SV *value)
    CODE:
        Promise__XS__Deferred* self = _get_deferred_from_sv(aTHX_ self_sv);

        if (self->promise->state != XSPR_STATE_PENDING) {
            croak("Cannot resolve deferred: not pending");
        }

        xspr_result_t* result = xspr_result_new(aTHX_ XSPR_RESULT_RESOLVED);
        result->result = newSVsv(value);

        xspr_promise_finish(aTHX_ self->promise, result);
        xspr_result_decref(aTHX_ result);

void
reject(SV *self_sv, SV *reason)
    CODE:
        Promise__XS__Deferred* self = _get_deferred_from_sv(aTHX_ self_sv);

        if (self->promise->state != XSPR_STATE_PENDING) {
            croak("Cannot reject deferred: not pending");
        }

        xspr_result_t* result = xspr_result_new(aTHX_ XSPR_RESULT_REJECTED);
        result->result = newSVsv(reason);

        xspr_promise_finish(aTHX_ self->promise, result);
        xspr_result_decref(aTHX_ result);

void
clear_unhandled_rejection(SV *self_sv)
    CODE:
        Promise__XS__Deferred* self = _get_deferred_from_sv(aTHX_ self_sv);
        self->promise->unhandled_rejection_sv = NULL;

bool
is_pending(SV *self_sv)
    CODE:
        Promise__XS__Deferred* self = _get_deferred_from_sv(aTHX_ self_sv);

        RETVAL = (self->promise->state == XSPR_STATE_PENDING);
    OUTPUT:
        RETVAL

void
DESTROY(SV *self_sv)
    CODE:
        Promise__XS__Deferred* self = _get_deferred_from_sv(aTHX_ self_sv);

        if (self->promise->detect_leak_yn) {
        }

        xspr_promise_decref(aTHX_ self->promise);
        Safefree(self);


MODULE = Promise::XS     PACKAGE = Promise::XS

void
then(SV* self_sv, ...)
    PPCODE:
        Promise__XS* self = _get_promise_from_sv(aTHX_ self_sv);

        //fprintf(stderr, "in PPCODE\n");
        SV* on_resolve;
        SV* on_reject;
        xspr_promise_t* next = NULL;

        if (items > 3) {
            croak_xs_usage(cv, "self, on_resolve, on_reject");
        }

        on_resolve = (items > 1) ? ST(1) : &PL_sv_undef;
        on_reject  = (items > 2) ? ST(2) : &PL_sv_undef;

        /* Many promises are just thrown away after the final callback, no need to allocate a next promise for those */
        if (GIMME_V != G_VOID) {
            PROMISE_CLASS_TYPE* next_promise;
            Newxz(next_promise, 1, PROMISE_CLASS_TYPE);

            next = xspr_promise_new(aTHX);
            next_promise->promise = next;

            ST(0) = sv_newmortal();
            sv_setref_pv(ST(0), PROMISE_CLASS, (void*)next_promise);
        }

        xspr_callback_t* callback = xspr_callback_new_perl(aTHX_ on_resolve, on_reject, next);
        xspr_promise_then(aTHX_ self->promise, callback);
        //fprintf(stderr, "end PPCODE\n");

        XSRETURN(1);

void
catch(SV* self_sv, SV* on_reject)
    PPCODE:
        Promise__XS* self = _get_promise_from_sv(aTHX_ self_sv);

        xspr_promise_t* next = NULL;

        /* Many promises are just thrown away after the final callback, no need to allocate a next promise for those */
        if (GIMME_V != G_VOID) {
            PROMISE_CLASS_TYPE* next_promise;
            Newxz(next_promise, 1, PROMISE_CLASS_TYPE);

            next = xspr_promise_new(aTHX);
            next_promise->promise = next;

            ST(0) = sv_newmortal();
            sv_setref_pv(ST(0), PROMISE_CLASS, (void*)next_promise);
        }

        xspr_callback_t* callback = xspr_callback_new_perl(aTHX_ &PL_sv_undef, on_reject, next);
        xspr_promise_then(aTHX_ self->promise, callback);

        XSRETURN(1);

void
finally(SV* self_sv, SV* on_finally)
    PPCODE:
        Promise__XS* self = _get_promise_from_sv(aTHX_ self_sv);

        xspr_promise_t* next = NULL;

        /* Many promises are just thrown away after the final callback, no need to allocate a next promise for those */
        if (GIMME_V != G_VOID) {
            PROMISE_CLASS_TYPE* next_promise;
            Newxz(next_promise, 1, PROMISE_CLASS_TYPE);

            next = xspr_promise_new(aTHX);
            next_promise->promise = next;

            ST(0) = sv_newmortal();
            sv_setref_pv(ST(0), PROMISE_CLASS, (void*)next_promise);
        }

        xspr_callback_t* callback = xspr_callback_new_finally(aTHX_ on_finally, next);
        xspr_promise_then(aTHX_ self->promise, callback);

        XSRETURN(1);

SV *
_unhandled_rejection_sr(SV* self_sv)
    CODE:
        Promise__XS* self = _get_promise_from_sv(aTHX_ self_sv);

        if (self->promise->unhandled_rejection_sv) {
            RETVAL = newRV_inc( newSVsv( self->promise->unhandled_rejection_sv ) );
        }
        else {
            RETVAL = NULL;
        }
    OUTPUT:
        RETVAL

void
DESTROY(SV* self_sv)
    CODE:
        Promise__XS* self = _get_promise_from_sv(aTHX_ self_sv);
        xspr_promise_decref(aTHX_ self->promise);
        Safefree(self);

