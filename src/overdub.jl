using Cassette

Cassette.@context CounterCtx;

const ternops = (
    (:fma32, Core.Intrinsics.fma_float, Float32),
    (:fma64, Core.Intrinsics.fma_float, Float64),
)

const binops = (
    (:add32, Core.Intrinsics.add_float, Float32),
    (:sub32, Core.Intrinsics.sub_float, Float32),
    (:mul32, Core.Intrinsics.mul_float, Float32),
    (:div32, Core.Intrinsics.div_float, Float32),
    (:add64, Core.Intrinsics.add_float, Float64),
    (:sub64, Core.Intrinsics.sub_float, Float64),
    (:mul64, Core.Intrinsics.mul_float, Float64),
    (:div64, Core.Intrinsics.div_float, Float64),
)

const unops = (
    (:sqrt32, Core.Intrinsics.sqrt_llvm, Float32),
    (:sqrt64, Core.Intrinsics.sqrt_llvm, Float64),
)

const ops = Iterators.flatten((ternops, binops, unops)) |> collect

@eval mutable struct Counter
    $((:($(op[1]) ::Int) for op in ops)...)
    Counter() = new($((0 for _ in 1:length(ops))...))
end

for typ1 in (Float32, Float64)
    @eval function Cassette.prehook(ctx::CounterCtx,
                                    op::Core.IntrinsicFunction,
                                    ::$typ1,
                                    ::$typ1,
                                    ::$typ1)
        $(Expr(:block,
               (map(ternops) do (name, op, typ2)
                  typ1 == typ2 || return :nothing
                  quote
                    if op == $op
                       ctx.metadata.$name += 1
                       return
                    end
                  end
                end)...))
    end

    @eval function Cassette.prehook(ctx::CounterCtx,
                                    op::Core.IntrinsicFunction,
                                    ::$typ1,
                                    ::$typ1)
        $(Expr(:block,
               (map(binops) do (name, op, typ2)
                  typ1 == typ2 || return :nothing
                  quote
                    if op == $op
                       ctx.metadata.$name += 1
                       return
                    end
                  end
                end)...))
    end

    @eval function Cassette.prehook(ctx::CounterCtx,
                                    op::Core.IntrinsicFunction,
                                    ::$typ1)
        $(Expr(:block,
               (map(unops) do (name, op, typ2)
                  typ1 == typ2 || return :nothing
                  quote
                    if op == $op
                       ctx.metadata.$name += 1
                       return
                    end
                  end
                end)...))
    end
end


# Relatively inefficient, but there should be no need for performance here...

function flop(c::Counter)
    total = 2 * (c.fma32 + c.fma64)
    total += c.add32 + c.add64
    total += c.sub32 + c.sub64
    total += c.div32 + c.div64
    total += c.mul32 + c.mul64
    total += c.sqrt32 + c.sqrt64
    total
end

import Base: ==, *, show

function Base.show(io::IO, c::Counter)
    println(io, "Flop Counter:")
    for field in fieldnames(Counter)
        println(io, " $field: $(getfield(c, field))")
    end
end

function ==(c1::Counter, c2::Counter)
    all(getfield(c1, field)==getfield(c2, field) for field in fieldnames(Counter))
end

function *(n::Int, c::Counter)
    ret = Counter()
    for field in fieldnames(Counter)
        setfield!(ret, field, n*getfield(c, field))
    end
    ret
end
