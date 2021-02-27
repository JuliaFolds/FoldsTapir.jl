module FoldsTapir

export TapirEx, StaticTapirEx

using Base.Experimental: Tapir

import Transducers
const FoldsBase = Transducers

struct TapirEx{K} <: FoldsBase.Executor
    kwargs::K
end

using Accessors: @set
using SplittablesBase: amount
using Transducers:
    @return_if_reduced,
    Reduced,
    Transducer,
    Transducers,
    combine,
    complete,
    opcompose,
    start,
    transduce,
    unreduced

# TODO: Don't import internals from Transducers:
using Transducers:
    CancellableDACContext,
    DefaultInitOf,
    EmptyResultError,
    NoopDACContext,
    Reducible,
    SizedReducible,
    _halve,
    _might_return_reduced,
    _reduce_basecase,
    _reducingfunction,
    cancel!,
    combine_right_reduced,
    foldl_nocomplete,
    issmall,
    maybe_usesimd,
    retransform,
    should_abort,
    splitcontext

include("utils.jl")
include("tapir.jl")
include("static.jl")

_static_nthreads_(::Any) = Val(1)
static_nthreads() = _static_nthreads_(nothing)

function __init__()
    @eval _static_nthreads_(::Nothing) = Val($(Threads.nthreads()))
end

end
