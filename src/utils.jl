const SIMDFlag = Union{Bool, Symbol, Val{true}, Val{false}, Val{:ivdep}}

"""
    asval(T, x) -> v::Val{x′::T}

`asval(T, x)` validates `x` and returns `Val(x′)` such that `x′ isa T` and
`x == T(x′)`.
"""
function asval(::Type{T}, v::Val{x}) where {T,x}
    x isa T && return v
    error("expected type `$T` in `x` of `Val(x)`; got `x = $x`")
end
asval(::Type{T}, x::T) where {T} = Val(x)
asval(::Type{T}, x) where {T} = Val(T(x))

valueof(::Val{x}) where {x} = x
valueof(x) = x

# @generated foldlval(op, init, ::Val{N}) where {N} =
#     foldl((ex, i) -> :(op($ex, $i)), 1:N; init = :init)

@inline foldlargs(op, x) = x
@inline foldlargs(op, x1, x2, xs...) = foldlargs(op, op(x1, x2), xs...)

function zip_tuples(x::NTuple{N,Any}, xs::NTuple{N,Any}...) where {N}
    tuples = (x, xs...)
    return ntuple(i -> map(t -> t[i], tuples), Val{N}())
end

"""
    static_chunks(xs, ::Val{nchunks}) -> chunks::NTuple{nchunks}

Like `Iterators.partition(xs, cld(length(xs), nchunks))` but eagerly
partition `xs` and return a fixed-size tuple `chunks`. If `xs` is shorter
than `nchunks`, `chunks` contains empty chunks.
"""
function static_chunks end

function static_chunks(xs::AbstractArray, nchunks)
    basesize = cld(length(xs), valueof(nchunks))
    return ntuple(nchunks) do i
        @view xs[min(end+1,begin+(i-1)*basesize):min(end,begin+i*basesize-1)]
    end
end

function static_chunks(iter::Iterators.PartitionIterator{<:AbstractArray}, nchunks)
    xs = iter.c
    n = iter.n
    basesize = cld(length(xs), n * valueof(nchunks))
    return ntuple(nchunks) do i
        ys = @view xs[min(end+1,begin+(i-1)*basesize):min(end,begin+i*basesize-1)]
        Iterators.partition(ys, n)
    end
end

static_chunks(xs::Iterators.Zip, nchunks) =
    map(Base.splat(zip), zip_tuples(map(it -> static_chunks(it, nchunks), xs.is)...))
