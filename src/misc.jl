const GenericTapirEx = Union{TapirEx,StaticTapirEx}

function Base.NamedTuple(ex::GenericTapirEx)
    nts = ntuple(Val(nfields(ex))) do i
        (; fieldname(typeof(ex), i) => getfield(ex, i))
    end
    return foldl(merge, nts)
end

function Base.show(io::IO, ex::GenericTapirEx)
    @nospecialize ex
    print(io, nameof(typeof(ex)))
    print(io, NamedTuple(ex))
end


# FIXME: Compatibility for Folds.Testing:
# <Workaround>
function Base.getproperty(ex::GenericTapirEx, field::Symbol)
    if field === :kwargs
        return NamedTuple(ex)
    else
        return getfield(ex, field)
    end
end

ConstructionBase.getproperties(ex::GenericTapirEx) = (kwargs = NamedTuple(ex),)

ConstructionBase.setproperties(ex::GenericTapirEx, patch::NamedTuple{(:kwargs,)}) =
    ConstructionBase.constructorof(typeof(ex))(; patch.kwargs...)
# </Workaround>
