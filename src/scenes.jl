
"""
    Scene TODO document this

## Constructors
$(SIGNATURES)

## Fields
$(FIELDS)
"""
mutable struct Scene <: AbstractScene
    "The parent of the Scene; if it is a top-level Scene, `parent == nothing`."
    parent::Union{Nothing, Scene}

    "[`Events`](@ref) associated with the Scene."
    events::Events

    "The current pixel area of the Scene."
    px_area::Observable{Rect2i}

    "Whether the scene should be cleared."
    clear::Bool

    "The `Camera` associated with the Scene."
    camera::Camera

    "The controls for the camera of the Scene."
    camera_controls::AbstractCamera

    "The [`Transformation`](@ref) of the Scene."
    transformation::Transformation

    "The plots contained in the Scene."
    plots::Vector{AbstractPlot}

    theme::Attributes

    "Children of the Scene inherit its transformation."
    children::Vector{Scene}

    """
    The Screens which the Scene is displayed to.
    """
    current_screens::Vector{AbstractScreen}

    # Attributes
    backgroundcolor::Observable{RGBAf}
    visible::Observable{Bool}
end

get_scene(scene::Scene) = scene

_plural_s(x) = length(x) != 1 ? "s" : ""

function Base.show(io::IO, scene::Scene)
    println(io, "Scene ($(size(scene, 1))px, $(size(scene, 2))px):")
    print(io, "  $(length(scene.plots)) Plot$(_plural_s(scene.plots))")

    if length(scene.plots) > 0
        print(io, ":")
        for (i, plot) in enumerate(scene.plots)
            print(io, "\n")
            print(io, "    $(i == length(scene.plots) ? '└' : '├') ", plot)
        end
    end

    print(io, "\n  $(length(scene.children)) Child Scene$(_plural_s(scene.children))")

    if length(scene.children) > 0
        print(io, ":")
        for (i, subscene) in enumerate(scene.children)
            print(io, "\n")
            print(io,"    $(i == length(scene.children) ? '└' : '├') Scene ($(size(subscene, 1))px, $(size(subscene, 2))px)")
        end
    end
end

function Scene(;
        px_area::Union{Observable{Rect2i}, Nothing} = nothing,
        events::Events = Events(),
        clear::Bool = true,
        transform_func=identity,
        camera::Union{Function, Camera, Nothing} = nothing,
        camera_controls::AbstractCamera = EmptyCamera(),
        transformation::Transformation = Transformation(transform_func),
        plots::Vector{AbstractPlot} = AbstractPlot[],
        theme::Attributes = Attributes(),
        children::Vector{Scene} = Scene[],
        current_screens::Vector{AbstractScreen} = AbstractScreen[],
        parent = nothing,
        visible = Observable(true),
        theme_kw...
    )
    m_theme = current_default_theme(; theme..., theme_kw...)

    bg = map(to_color, m_theme.backgroundcolor)

    wasnothing = isnothing(px_area)
    if wasnothing
        px_area = lift(m_theme.resolution) do res
            Recti(0, 0, res)
        end
    end

    cam = camera isa Camera ? camera : Camera(px_area)
    if wasnothing
        on(events.window_area, priority = typemax(Int8)) do w_area
            if !any(x -> x ≈ 0.0, widths(w_area)) && px_area[] != w_area
                px_area[] = w_area
            end
            return Consume(false)
        end
    end
    scene = Scene(
        parent, events, px_area, clear, cam, camera_controls,
        transformation, plots, m_theme,
        children, current_screens, bg, visible
    )
    if camera isa Function
        cam = camera(scene)
    end
    return scene
end

function Scene(
        parent::Scene;
        events=parent.events,
        px_area=nothing,
        clear=false,
        camera=nothing,
        camera_controls=parent.camera_controls,
        transformation=Transformation(parent),
        theme=theme(parent),
        current_screens=parent.current_screens,
        kw...
    )
    if isnothing(px_area)
        px_area = lift(zero_origin, parent.px_area)
    else
        px_area = lift(pixelarea(parent), convert(Observable, px_area)) do p, a
            # make coordinates relative to parent
            rect = Rect2i(minimum(p) .+ minimum(a), widths(a))
            return rect
        end
    end
    if camera !== parent.camera
        camera_controls = EmptyCamera()
    end
    child = Scene(;
        events=events,
        px_area=px_area,
        clear=clear,
        camera=camera,
        camera_controls=camera_controls,
        parent=parent,
        transformation=transformation,
        theme=theme,
        current_screens=current_screens,
        kw...
    )
    push!(parent.children, child)
    child.parent = parent
    return child
end

# legacy constructor
function Scene(parent::Scene, area; kw...)
    return Scene(parent; px_area=area, kw...)
end

# Base overloads for Scene
Base.parent(scene::Scene) = scene.parent
isroot(scene::Scene) = parent(scene) === nothing
rootparent(x) = rootparent(parent(x))
rootparent(x::Scene) = x

function root(scene::Scene)
    while !isroot(scene)
        scene = parent(scene)
    end
    scene
end
parent_or_self(scene::Scene) = isroot(scene) ? scene : parent(scene)

GeometryBasics.widths(scene::Scene) = widths(to_value(pixelarea(scene)))

Base.size(scene::Scene) = Tuple(widths(scene))
Base.size(x::Scene, i) = size(x)[i]
function Base.resize!(scene::Scene, xy::Tuple{Number,Number})
    resize!(scene, Recti(0, 0, xy))
end
Base.resize!(scene::Scene, x::Number, y::Number) = resize!(scene, (x, y))
function Base.resize!(scene::Scene, rect::Rect2)
    pixelarea(scene)[] = rect
end

"""
    getscreen(scene::Scene)

Gets the current screen a scene is associated with.
Returns nothing if not yet displayed on a screen.
"""
function getscreen(scene::Scene)
    if isempty(scene.current_screens)
        isroot(scene) && return nothing # stop search
        return getscreen(parent(scene)) # screen could be in parent
    end
    # TODO, when would we actually want to get a specific screen?
    return last(scene.current_screens)
end

getscreen(scene::SceneLike) = getscreen(rootparent(scene))

# Just indexing into a scene gets you plot 1, plot 2 etc
Base.iterate(scene::Scene, idx=1) = idx <= length(scene) ? (scene[idx], idx + 1) : nothing
Base.length(scene::Scene) = length(scene.plots)
Base.lastindex(scene::Scene) = length(scene.plots)
getindex(scene::Scene, idx::Integer) = scene.plots[idx]
struct OldAxis end

zero_origin(area) = Recti(0, 0, widths(area))

function child(scene::Scene; camera, attributes...)
    return Scene(scene, lift(zero_origin, pixelarea(scene)); camera=camera, attributes...)
end

"""
Creates a subscene with a pixel camera
"""
function cam2d(scene::Scene)
    return child(scene, clear=false, camera=cam2d!)
end

function campixel(scene::Scene)
    return child(scene, clear=false, camera=campixel!)
end

function getindex(scene::Scene, ::Type{OldAxis})
    for plot in scene
        isaxis(plot) && return plot
    end
    return nothing
end

function Base.empty!(scene::Scene)
    empty!(scene.plots)
    disconnect!(scene.camera)
    scene.camera_controls[] = EmptyCamera()
    empty!(scene.theme)
    merge!(scene.theme, _current_default_theme)
    empty!(scene.children)
    empty!(scene.current_screens)
end

Base.push!(scene::Combined, subscene) = nothing # Combined plots add themselves uppon creation

function Base.push!(scene::Scene, plot::AbstractPlot)
    push!(scene.plots, plot)
    plot isa Combined || (plot.parent[] = scene)
    for screen in scene.current_screens
        insert!(screen, scene, plot)
    end
end

function Base.delete!(screen::AbstractScreen, ::Scene, ::AbstractPlot)
    @warn "Deleting plots not implemented for backend: $(typeof(screen))"
end

function Base.delete!(scene::Scene, plot::AbstractPlot)
    len = length(scene.plots)
    filter!(x -> x !== plot, scene.plots)
    if length(scene.plots) == len
        error("$(typeof(plot)) not in scene!")
    end
    for screen in scene.current_screens
        delete!(screen, scene, plot)
    end
end

function Base.push!(scene::Scene, child::Scene)
    push!(scene.children, child)
    disconnect!(child.camera)
    nodes = map([:view, :projection, :projectionview, :resolution, :eyeposition]) do field
        lift(getfield(scene.camera, field)) do val
            getfield(child.camera, field)[] = val
            getfield(child.camera, field)[] = val
        end
    end
    cameracontrols!(child, nodes)
    child.parent = scene
    return scene
end

events(scene::Scene) = scene.events
events(scene::SceneLike) = events(scene.parent)

camera(scene::Scene) = scene.camera
camera(scene::SceneLike) = camera(scene.parent)

cameracontrols(scene::Scene) = scene.camera_controls
cameracontrols(scene::SceneLike) = cameracontrols(scene.parent)

function cameracontrols!(scene::Scene, cam)
    disconnect!(scene.camera_controls)
    scene.camera_controls = cam
    return cam
end
cameracontrols!(scene::SceneLike, cam) = cameracontrols!(parent(scene), cam)

pixelarea(scene::Scene) = scene.px_area
pixelarea(scene::SceneLike) = pixelarea(scene.parent)

plots(scene::SceneLike) = scene.plots

"""
Fetches all plots sharing the same camera
"""
plots_from_camera(scene::Scene) = plots_from_camera(scene, scene.camera)
function plots_from_camera(scene::Scene, camera::Camera, list=AbstractPlot[])
    append!(list, scene.plots)
    for child in scene.children
        child.camera == camera && plots_from_camera(child, camera, list)
    end
    list
end

"""
Flattens all the combined plots and returns a Vector of Atomic plots
"""
function flatten_combined(plots::Vector, flat=AbstractPlot[])
    for elem in plots
        if (elem isa Combined)
            flatten_combined(elem.plots, flat)
        else
            push!(flat, elem)
        end
    end
    flat
end

function insertplots!(screen::AbstractDisplay, scene::Scene)
    for elem in scene.plots
        insert!(screen, scene, elem)
    end
    foreach(child -> insertplots!(screen, child), scene.children)
end

update_cam!(scene::Scene, bb::AbstractCamera, rect) = nothing

function center!(scene::Scene, padding=0.01)
    bb = boundingbox(scene)
    bb = transformationmatrix(scene)[] * bb
    w = widths(bb)
    padd = w .* padding
    bb = Rect3f(minimum(bb) .- padd, w .+ 2padd)
    update_cam!(scene, bb)
    scene
end

parent_scene(x::Combined) = parent_scene(parent(x))
parent_scene(x::Scene) = x

Base.isopen(x::SceneLike) = events(x).window_open[]

function is2d(scene::SceneLike)
    lims = data_limits(scene)
    lims === nothing && return nothing
    return is2d(lims)
end
is2d(lims::Rect2) = true
is2d(lims::Rect3) = widths(lims)[3] == 0.0

#####
##### Figure type
#####

struct Figure
    scene::Scene
    layout::GridLayoutBase.GridLayout
    content::Vector
    attributes::Attributes
    current_axis::Ref{Any}

    function Figure(args...)
        f = new(args...)
        current_figure!(f)
        f
    end
end

struct FigureAxisPlot
    figure::Figure
    axis
    plot::AbstractPlot
end

const FigureLike = Union{Scene, Figure, FigureAxisPlot}
