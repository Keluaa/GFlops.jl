prepare_call!(vars, expr) = expr
prepare_call!(vars, s::Symbol) = esc(s)

function prepare_call!(vars, e::Expr)
    e.head == :$ || return Expr(e.head, map(x->prepare_call!(vars, x), e.args)...)

    var = gensym()
    push!(vars, :($var = $(prepare_call!(vars, e.args[1]))))
    var
end

prepare_call(e) = let v=[]
    e2 = prepare_call!(v, e)
    v, e2
end




function count_ops(funcall, ignore_cmp=nothing)
    if ignore_cmp === nothing
        cmp = true
    elseif ignore_cmp isa Expr &&
            ignore_cmp.head === :(=) &&
            ignore_cmp.args[1] === :ignore_cmp
        # Expect `:(ignore_cmp=expr)`, and extract `expr`
        cmp = ignore_cmp.args[2]
    else
        error("Expected `ignore_cmp=truthy` as second argument, got: $ignore_cmp")
    end

    v, e = prepare_call(funcall)
    quote
        let
            meta = (; counter=Counter(), ignore_cmp=($cmp)::Bool)
            ctx = CounterCtx(metadata=meta)
            $(v...)
            Cassette.overdub(ctx, ()->begin
                             $e
                             end)
            ctx.metadata.counter
        end
    end
end

macro count_ops(funcall)
    count_ops(funcall)
end

macro count_ops(funcall, ignore_cmp)
    count_ops(funcall, ignore_cmp)
end



# Helper accessor (that can be overriden to fake benchmarking times in tests)
times(t::BenchmarkTools.Trial) = t.times


function gflops(funcall, ignore_cmp=nothing)
    benchmark = quote
        $BenchmarkTools.@benchmark $funcall
    end

    quote
        let
            b = $(esc(benchmark))
            ns = minimum(times(b))

            cnt = flop($(count_ops(funcall, ignore_cmp)))
            gflops = cnt / ns
            peakfraction = 1e9 * gflops / peakflops()
            memory = $BenchmarkTools.prettymemory(b.memory)
            @printf("  %.2f GFlops,  %.2f%% peak  (%.2e flop, %.2e s, %d alloc: %s)\n",
                    gflops, peakfraction*100, cnt, ns*1e-9,
                    b.allocs, memory)
            gflops
        end
    end
end


macro gflops(funcall)
    gflops(funcall)
end

macro gflops(funcall, ignore_cmp)
    gflops(funcall, ignore_cmp)
end
