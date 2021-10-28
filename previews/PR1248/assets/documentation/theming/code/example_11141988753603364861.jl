# This file was generated, do not modify it. # hide
__result = begin # hide
  
using CairoMakie
CairoMakie.activate!() # hide
Makie.inline!(true) # hide

f = Figure()

Axis(f[1, 1])

# the normal cycle
lines!(0..10, x -> sin(x) - 1)
lines!(0..10, x -> sin(x) - 2)
lines!(0..10, x -> sin(x) - 3)

# manually specified colors
lines!(0..10, x -> sin(x) - 5, color = Cycled(3))
lines!(0..10, x -> sin(x) - 6, color = Cycled(2))
lines!(0..10, x -> sin(x) - 7, color = Cycled(1))

f

  end # hide
  save(joinpath(@OUTPUT, "example_11141988753603364861.png"), __result) # hide
  
  nothing # hide