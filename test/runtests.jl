module TestFoldsTapir
using Test
using FoldsTapir

@info "Testing with" FoldsTapir.USE_TAPIR_OUTPUT

@testset "$file" for file in sort([
    file for file in readdir(@__DIR__) if match(r"^test_.*\.jl$", file) !== nothing
])
    include(file)
end

end  # module
