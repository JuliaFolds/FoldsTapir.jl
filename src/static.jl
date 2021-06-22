struct StaticTapirEx{NThreads,SIMD} <: FoldsBase.Executor
    nthreads::Val{NThreads}
    simd::Val{SIMD}
end

StaticTapirEx(;
    nthreads::Union{Val,Integer} = static_nthreads(),
    simd::SIMDFlag = Val(false),
    # stoppable::Union{Bool,Nothing} = nothing,
) = StaticTapirEx(
    asval(Int, nthreads),
    asval(Bool, simd),
    # asval(Union{Bool,Nothing}, stoppable),
)

Transducers.maybe_set_simd(ex::StaticTapirEx, simd) = @set ex.simd = asval(Bool, simd)

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
    accs = transduce_partitions(rf2, init, static_chunks(coll, ex.nthreads))
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
        Tapir.@sync begin
            $(spawns...)
        end
        return ($(accs...),)
    end
end

function Base.show(io::IO, ex::StaticTapirEx)
    @nospecialize ex
    print(
        io,
        StaticTapirEx,
        "(nthreads = ",
        Val,
        '(',
        valueof(ex.nthreads),
        "), simd = ",
        Val,
        '(',
        valueof(ex.simd),
        ')',
        ')',
    )
end
