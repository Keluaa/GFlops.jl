using Cassette

Cassette.@context CounterCtx;


const ternops = [
    (:fma, (Core.Intrinsics.fma_float,), 2), # 2 flops per FMA instruction
    (:muladd, (Core.Intrinsics.muladd_float,), 2), # 2 flops per muladd instruction
]

const binops = [
    (:add, (Core.Intrinsics.add_float, Core.Intrinsics.add_float_fast), 1),
    (:sub, (Core.Intrinsics.sub_float, Core.Intrinsics.sub_float_fast), 1),
    (:mul, (Core.Intrinsics.mul_float, Core.Intrinsics.mul_float_fast), 1),
    (:div, (Core.Intrinsics.div_float, Core.Intrinsics.div_float_fast), 1),
    (:sign, (Core.Intrinsics.copysign_float,), 1),
    (:cmp, (
        Core.Intrinsics.eq_float, Core.Intrinsics.eq_float_fast,
        Core.Intrinsics.le_float, Core.Intrinsics.le_float_fast,
        Core.Intrinsics.lt_float, Core.Intrinsics.lt_float_fast,
        Core.Intrinsics.ne_float, Core.Intrinsics.ne_float_fast,
        Core.Intrinsics.fpiseq
    ), 1),
]

const unops = [
    (:abs, (Core.Intrinsics.abs_float,), 1),
    (:neg, (Core.Intrinsics.neg_float, Core.Intrinsics.neg_float_fast), 1),
    (:sqrt, (Core.Intrinsics.sqrt_llvm, Core.Intrinsics.sqrt_llvm_fast), 1),
    (:ceil, (Core.Intrinsics.ceil_llvm,), 1),
    (:floor, (Core.Intrinsics.floor_llvm,), 1),
    (:trunc, (Core.Intrinsics.trunc_llvm,), 1),
    (:round, (Core.Intrinsics.rint_llvm,), 1),
]

@static if VERSION < v"1.10"
    push!(binops,
        (:rem, (Core.Intrinsics.rem_float, Core.Intrinsics.rem_float_fast), 1),
    )
end

const ops = Iterators.flatten((ternops, binops, unops)) |> collect

const typs = (
    (Float16, :16),
    (Float32, :32),
    (Float64, :64),
)


function gen_count(ops, suffix)
    body = Expr(:block)
    for (name, op_list) in ops
        fieldname = Symbol(name, suffix)
        e = quote
            if op in $op_list
                ctx.metadata.$fieldname += 1
                return
            end
        end
        push!(body.args, e)
    end
    body
end

for (typ, suffix) in typs
    @eval function Cassette.prehook(ctx::CounterCtx,
                                    op::Core.IntrinsicFunction,
                                    ::$typ,
                                    ::$typ,
                                    ::$typ)
        $(gen_count(ternops, suffix))
    end

    @eval function Cassette.prehook(ctx::CounterCtx,
                                    op::Core.IntrinsicFunction,
                                    ::$typ,
                                    ::$typ)
        $(gen_count(binops, suffix))
    end

    @eval function Cassette.prehook(ctx::CounterCtx,
                                    op::Core.IntrinsicFunction,
                                    ::$typ)
        $(gen_count(unops, suffix))
    end
end
