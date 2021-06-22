Transducers.transduce(xf, rf, init, xs, ex::TapirEx) =
    _transduce(xf, rf, init, xs; ex.kwargs...)

function _transduce(
    xform::Transducer,
    step::F,
    init,
    coll0;
    simd::SIMDFlag = Val(false),
    basesize::Union{Integer,Nothing} = nothing,
    stoppable::Union{Bool,Nothing} = nothing,
) where {F}
    rf0 = _reducingfunction(xform, step; init = init)
    rf, coll = retransform(rf0, coll0)
    if stoppable === nothing
        stoppable = _might_return_reduced(rf, init, coll)
    end
    acc = @return_if_reduced _reduce(
        stoppable ? CancellableDACContext() : NoopDACContext(),
        maybe_usesimd(rf, simd),
        init,
        SizedReducible(
            coll,
            basesize === nothing ? amount(coll) ÷ Threads.nthreads() : basesize,
        ),
    )
    result = complete(rf, acc)
    if unreduced(result) isa DefaultInitOf
        throw(EmptyResultError(rf))
    end
    return result
end

function _reduce(ctx, rf::R, init::I, reducible::Reducible) where {R,I}
    if should_abort(ctx)
        return init
    end
    if issmall(reducible)
        acc = _reduce_basecase(rf, init, reducible)
        if acc isa Reduced
            cancel!(ctx)
        end
        return acc
    else
        left, right = _halve(reducible)
        fg, bg = splitcontext(ctx)
        @static if USE_TAPIR_OUTPUT
            Tapir.@output a0 b0
            Tapir.@sync begin
                Tapir.@spawn b0 = _reduce(bg, rf, init, right)
                a0 = _reduce(fg, rf, init, left)
            end
        else
            Tapir.@sync begin
                Tapir.@spawn $b0 = _reduce(bg, rf, init, right)
                $a0 = _reduce(fg, rf, init, left)
            end
        end
        a = @return_if_reduced a0
        should_abort(ctx) && return a  # slight optimization
        b0 isa Reduced && return combine_right_reduced(rf, a, b0)
        return combine(rf, a, b0)
    end
end
