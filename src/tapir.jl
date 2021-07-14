struct TapirEx{
    Basesize<:Union{Integer,Nothing},
    SIMD,
    Stoppable<:Union{Bool,Nothing},
    TaskGroup,
} <: FoldsBase.Executor
    basesize::Basesize
    simd::Val{SIMD}
    stoppable::Stoppable
    taskgroup::TaskGroup

    TapirEx(
        basesize::Basesize,
        simd::Val{SIMD},
        stoppable::Stoppable,
        taskgroup::TaskGroup,
    ) where {Basesize,SIMD,Stoppable,TaskGroup} =
        new{Basesize,SIMD,Stoppable,Core.Typeof(taskgroup)}(
            basesize,
            simd,
            stoppable,
            taskgroup,
        )
end

TapirEx(;
    basesize::Union{Integer,Nothing} = nothing,
    simd::SIMDFlag = Val(false),
    stoppable::Union{Bool,Nothing} = nothing,
    taskgroup = Tapir.taskgroup,
) = TapirEx(basesize, asval(Bool, simd), stoppable, taskgroup)

Transducers.transduce(xf, rf, init, xs, ex::TapirEx) = _transduce(xf, rf, init, xs, ex)

function _transduce(xform::Transducer, step::F, init, coll0, ex::TapirEx) where {F}
    (; basesize, simd, stoppable, taskgroup) = ex
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
        taskgroup,
    )
    result = complete(rf, acc)
    if unreduced(result) isa DefaultInitOf
        throw(EmptyResultError(rf))
    end
    return result
end

function _reduce(ctx, rf::R, init::I, reducible::Reducible, taskgroup) where {R,I}
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
            Tapir.@sync taskgroup() begin
                Tapir.@spawn b0 = _reduce(bg, rf, init, right, taskgroup)
                a0 = _reduce(fg, rf, init, left, taskgroup)
            end
        else
            Tapir.@sync taskgroup() begin
                Tapir.@spawn $b0 = _reduce(bg, rf, init, right, taskgroup)
                $a0 = _reduce(fg, rf, init, left, taskgroup)
            end
        end
        a = @return_if_reduced a0
        should_abort(ctx) && return a  # slight optimization
        b0 isa Reduced && return combine_right_reduced(rf, a, b0)
        return combine(rf, a, b0)
    end
end
