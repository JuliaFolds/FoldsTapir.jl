module FoldsTapir

export TapirEx

using Base.Experimental: Tapir

import Transducers
const FoldsBase = Transducers

struct TapirEx{K} <: FoldsBase.Executor
    kwargs::K
end

using SplittablesBase: amount
using Transducers:
    @return_if_reduced,
    Reduced,
    Transducer,
    Transducers,
    combine,
    complete,
    opcompose,
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
    issmall,
    maybe_usesimd,
    retransform,
    should_abort,
    splitcontext

const SIMDFlag = Union{Bool, Symbol, Val{true}, Val{false}, Val{:ivdep}}

include("tapir.jl")

end
