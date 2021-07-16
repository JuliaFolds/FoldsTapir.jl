struct StaticTapirEx{NThreads,SIMD,TaskGroup} <: FoldsBase.Executor
    nthreads::Val{NThreads}
    simd::Val{SIMD}
    taskgroup::TaskGroup

    StaticTapirEx(
        nthreads::Val{NThreads},
        simd::Val{SIMD},
        taskgroup::TaskGroup,
    ) where {NThreads,SIMD,TaskGroup} =
        new{NThreads,SIMD,Core.Typeof(taskgroup)}(nthreads, simd, taskgroup)
end

StaticTapirEx(;
    nthreads::Union{Val,Integer} = static_nthreads(),
    simd::SIMDFlag = Val(false),
    # stoppable::Union{Bool,Nothing} = nothing,
    taskgroup = Tapir.taskgroup,
) = StaticTapirEx(
    asval(Int, nthreads),
    asval(Bool, simd),
    # asval(Union{Bool,Nothing}, stoppable),
    taskgroup,
)

@inline function Transducers.transduce(
    xf::XF,
    rf::RF,
    init,
    xs,
    ex::StaticTapirEx,
) where {XF,RF}
    rf0 = _reducingfunction(xf, rf; init = init)
    rf1, coll = retransform(rf0, xs)
    rf2 = maybe_usesimd(rf1, ex.simd)
    accs = transduce_partitions(rf2, init, static_chunks(coll, ex.nthreads), ex.taskgroup)
    result = complete(rf2, foldlargs((a, b) -> combine(rf, a, b), accs...))
    if unreduced(result) isa DefaultInitOf
        throw(EmptyResultError(rf2))
    end
    return result
end

# **For now** (at least), we need to use `@generated` for unrolling `@spawn`
# because syncregion cannot cross function boundaries.
@generated function transduce_partitions(
    rf::RF,
    init,
    partitions::NTuple{N,Any},
    taskgroup,
) where {RF,N}
    accs = [Symbol(:acc, i) for i in 1:N]
    spawns = map(1:N) do i
        # Like `_reduce_basecase` but without `SizedReducible`:
        if USE_TAPIR_OUTPUT
            lhs = accs[i]
        else
            lhs = Expr(:$, accs[i])
        end
        basecase = :($lhs = foldl_nocomplete(rf, start(rf, init), partitions[$i]))
        if i < N
            :(Tapir.@spawn $basecase)
        else
            basecase  # run the last basecase in the root
        end
    end
    header = if USE_TAPIR_OUTPUT
        :(Tapir.@output($(accs...),))
    else
        :(local $(accs...))
        nothing
    end
    quote
        Base.@_inline_meta
        $header
        Tapir.@sync taskgroup() begin
            $(spawns...)
        end
        return ($(accs...),)
    end
end

struct StaticPartitonIterator{Partitions}
    partitions::Partitions
end
# TODO: actually implement `iterate`

"""
    FoldsTapir.static_partition(xs, [n])

Like `Iterators.partition`, but for `StaticTapirEx`.
"""
function static_partition(xs, n = static_nthreads())
    partitions = map(tuple, static_chunks(xs, n))
    return StaticPartitonIterator(partitions)
end

static_chunks(itr::StaticPartitonIterator, _) = itr.partitions

Transducers.executor_type(::StaticPartitonIterator) = StaticTapirEx
