module G4Visualization
    using Geant4
    using Makie
    using Colors

    import Base: convert

    export draw, draw!, Vector3, RotMatrix3, Transformation3D

    include("Transformation3D.jl")

    function convert(::Type{Vector3{Float64}}, v::G4ThreeVector)
        Vector3{Float64}(x(v), y(v), z(v))
    end
    function convert(::Type{RotMatrix3{Float64}}, r::CxxPtr{G4RotationMatrix})
        if r == C_NULL
            one(RotMatrix3{Float64})
        else  
            RotMatrix3{Float64}(xx(r[]), yx(r[]), zx(r[]), xy(r[]), yy(r[]), zy(r[]), xz(r[]), yz(r[]), zz(r[]))
        end
    end

    function convert(::Type{Tuple{RGB, Float64}}, c::ConstCxxRef{G4Colour})
        return (RGB(GetRed(c),GetGreen(c), GetBlue(c)),GetAlpha(c))
    end

    function GeometryBasics.Tesselation(s::G4VSolid, nvertices::NTuple{N,<:Integer}) where N
        return Tesselation{3,Float64,typeof(s),N}(s, Int.(nvertices))
    end
    GeometryBasics.mesh(s::G4VSolid) = GeometryBasics.mesh(Tesselation(s, 64), facetype=typeof(first(GeometryBasics.faces(s))))
 
    colors = colormap("Grays", 6)

    function draw(pv::G4VPhysicalVolume; wireframe::Bool=false, maxlevel::Int64=999)
        lv = GetLogicalVolume(pv)
        fig = Figure(resolution=(1280, 720))
        s = LScene(fig[1,1])
        draw!(s, lv[], one(Transformation3D{Float64}), 1, wireframe, maxlevel)
        display(fig)
    end
    function draw!(s::LScene, pv::G4VPhysicalVolume; wireframe::Bool=false, maxlevel::Int64=999)
        lv = GetLogicalVolume(pv)
        draw!(s, lv[], one(Transformation3D{Float64}), 1, wireframe, maxlevel)
    end

    using Geant4.SystemOfUnits:cm3,g

    function GetReplicaParameters(pv::CxxPtr{G4VPhysicalVolume})
        axis = Ref{EAxis}(kYAxis)
        nReplicas = Ref{Int32}(0)
        width = Ref{Float64}(0.)
        offset = Ref{Float64}(0.)
        consuming = Ref{UInt8}(0)
        GetReplicationData(pv, axis, nReplicas, width, offset, consuming)
        return (axis[], nReplicas[], width[])
    end

    const UnitOnAxis = [(1,0,0), (0,1,0), (0,0,1)]

    function draw!(s::LScene, lv::G4LogicalVolume, t::Transformation3D{Float64}, level::Int64, wireframe::Bool, maxlevel::Int64)
        vsolid = GetSolid(lv)
        tsolid = GetEntityType(vsolid)
        shape =  getproperty(Main,Symbol(tsolid))
        solid = CxxRef{shape}(vsolid)
        m = GeometryBasics.mesh(solid[])
        if ! isone(t)
            points = GeometryBasics.coordinates(m)
            faces  = GeometryBasics.faces(m)
            map!(c -> c * t, points, points)
            m = GeometryBasics.Mesh(points, faces)
        end
        g4vis = GetVisAttributes(lv)
        color = g4vis != C_NULL ? convert(Tuple{RGB, Float64}, GetColour(g4vis)) : (colors[level], GetDensity(GetMaterial(lv))/(12g/cm3))
        visible = g4vis != C_NULL ? IsVisible(g4vis) : true
        if wireframe
            wireframe!(s, m, linewidth=1, visible=visible )
        else
            mesh!(s, m, color=color, transparency=true, visible=visible )
        end
        # Go down to the daughters
        if level < maxlevel
            for idx in 1:GetNoDaughters(lv)
                daughter = GetDaughter(lv, idx-1)
                if IsReplicated(daughter)
                    volume = GetLogicalVolume(daughter)
                    axis, nReplicas, width = GetReplicaParameters(daughter)
                    unitV = G4ThreeVector(UnitOnAxis[axis+1]...)
                    for i in 1:nReplicas
                        g4t = unitV * (-width*(nReplicas-1)*0.5 + (i-1)*width)
                        transformation = Transformation3D{Float64}(one(RotMatrix3{Float64}), convert(Vector3{Float64}, g4t))
                        draw!(s, volume[], transformation * t, level+1, wireframe, maxlevel)
                    end
                else    
                    g4t = GetTranslation(daughter)
                    g4r = GetRotation(daughter)
                    transformation = Transformation3D{Float64}(convert(RotMatrix3{Float64}, g4r), convert(Vector3{Float64}, g4t))
                    volume = GetLogicalVolume(daughter)
                    draw!(s, volume[], transformation * t, level+1, wireframe, maxlevel)
                end
            end
        end
    end

    #---G4Box--------------------------------------------------------------------------------------
    function GeometryBasics.coordinates(box::G4Box, facets=6)
        x, y, z = GetXHalfLength(box), GetYHalfLength(box), GetZHalfLength(box)
        return Point3{Float64}[(-x,-y,-z), ( x,-y,-z), (-x, y,-z), ( x, y,-z),
                         (-x,-y, z), ( x,-y, z), (-x, y, z), ( x, y, z)]
    end
    
    function GeometryBasics.faces(::G4Box, facets=6)
        iface = ((1,5,6,2),(3,4,8,7),(1,3,7,5),(2,6,8,4),(1,2,4,3),(5,6,8,7))
        (QuadFace{Int64}(f...) for f in iface)
    end
    function GeometryBasics.normals(::G4Box, facets=6)
        v = 1/√3
        return Vector3{Float64}[(-v,-v,-v), ( v,-v,-v), (-v, v,-v), ( v, v,-v),
                                (-v,-v, v), ( v,-v, v), (-v, v, v), ( v, v, v)]
    end    
    #---G4Trd--------------------------------------------------------------------------------------
    function GeometryBasics.coordinates(trd::G4Trd, facets=6)
        x1 = GetXHalfLength1(trd)
        x2 = GetXHalfLength2(trd)
        y1 = GetYHalfLength1(trd)
        y2 = GetYHalfLength2(trd)
        z  = GetZHalfLength(trd)
        Point3{Float64}[(-x1,-y1,-z), ( x1,-y1,-z), (-x1, y1,-z), ( x1, y1,-z),
        (-x2,-y2, z), ( x2,-y2, z), (-x2, y2, z), ( x2, y2, z)]
    end
    
    function GeometryBasics.faces(::G4Trd, facets=6)
        iface = ((1,5,6,2),(3,4,8,7),(1,3,7,5),(2,6,8,4),(1,2,4,3),(5,6,8,7))
        (QuadFace{Int64}(f...) for f in iface)
    end
    #---G4Cons--------------------------------------------------------------------------------------
    function GeometryBasics.coordinates(cone::G4Cons, facets=36)
        rmin1 = GetInnerRadiusMinusZ(cone)
        rmax1 = GetOuterRadiusMinusZ(cone)
        rmin2 = GetInnerRadiusPlusZ(cone)
        rmax2 = GetOuterRadiusPlusZ(cone)
        z     = GetZHalfLength(cone)
        ϕ₀    = GetStartPhiAngle(cone)
        Δϕ    = GetDeltaPhiAngle(cone)

        issector = Δϕ < 2π
        ishollow = rmin1 > 0 || rmin2 > 0
        issector ?  facets =  round(Int64, (facets/2π) * Δϕ) : nothing
        isodd(facets) ? facets = 2 * div(facets, 2) : nothing
        facets < 8 ? facets = 8 : nothing
        nbf = Int(facets / 2)            # Number of faces
        nbv = issector ? nbf + 1 : nbf   # Number of vertices
        nbc = ishollow ? nbv : 1         # Number of centers
        range = 1:(2*nbv + 2*nbc)
        function inner(i)
            return if i <= 2*nbv
                ϕ = ϕ₀ + (Δϕ * (((i + 1) ÷ 2) - 1)) / nbf
                isodd(i) ? Point(rmax2 * cos(ϕ), rmax2 * sin(ϕ), z) : Point(rmax1 * cos(ϕ), rmax1 * sin(ϕ), -z)
            elseif ishollow
                ϕ = ϕ₀ + (Δϕ * (((i - 2 * nbv + 1) ÷ 2) - 1)) / nbf
                isodd(i) ? Point(rmin2 * cos(ϕ), rmin2 * sin(ϕ), z) : Point(rmin1 * cos(ϕ), rmin1 * sin(ϕ), -z)
            elseif i == length(range)
                Point(0., 0., -z)
            elseif i == length(range) - 1
                Point(0., 0., z)
            end
        end
        return (inner(i) for i in range)
    end
    
    function GeometryBasics.faces(cone::G4Cons, facets=36)
        rmin1 = GetInnerRadiusMinusZ(cone)
        rmin2 = GetInnerRadiusPlusZ(cone)
        Δϕ    = GetDeltaPhiAngle(cone)
        
        issector = Δϕ < 2π
        ishollow = rmin1 > 0 || rmin2 > 0
        issector ?  facets =  round(Int64, (facets/2π) * Δϕ) : nothing
        isodd(facets) ? facets = 2 * div(facets, 2) : nothing
        facets < 8 ? facets = 8 : nothing
        nbf = Int(facets / 2)            # Number of faces
        nbv = issector ? nbf + 1 : nbf   # Number of vertices
        nbc = ishollow ? nbv : 1         # Number of centers
        indexes = Vector{QuadFace{Int64}}()
        for j in 1:nbf
            a,b = 2j-1, 2j
            c,d = !issector && j == nbf ? (1, 2) : (2j+1, 2j+2) 
            push!(indexes, (a,b,d,c))
            if ishollow
                a′,b′ = 2j-1+2nbv, 2j+2nbv
                c′,d′ = !issector && j == nbf ? (2nbv+1, 2nbv+2) : (2j+1+2nbv, 2j+2+2nbv)
                # inner wall
                push!(indexes, (a′,b′,d′,c′))
                # top
                push!(indexes, (c, c′, a′, a))
                # bottom
                push!(indexes, (b, b′, d′, d))
            else
                a′,b′ = 2nbv+1, 2nbv+2
                # top
                push!(indexes, (a′,a, c, c))
                # bottom
                push!(indexes, (b′,d, b, b))
            end
        end
        if issector
            # wedge walls
            a, b, c, d  = ( 1, 2, 2nbv-1, 2nbv)
            a′,b′,c′,d′ = ishollow ? (2nbv+1, 2nbv+2, 4nbv-1, 4nbv ) : (2nbv+1, 2nbv+2, 2nbv+1, 2nbv+2)
            push!(indexes, (a,  b, b′, a′))
            push!(indexes, (c′, d′, d, c ))
        end
        return indexes
    end

    #---G4Tubs--------------------------------------------------------------------------------------
    function GeometryBasics.coordinates(tub::G4Tubs, facets=36)
        rmin = GetInnerRadius(tub)
        rmax = GetOuterRadius(tub)
        z     = GetZHalfLength(tub)
        ϕ₀    = GetStartPhiAngle(tub)
        Δϕ    = GetDeltaPhiAngle(tub)

        issector = Δϕ < 2π
        ishollow = rmin > 0
        issector ?  facets =  round(Int64, (facets/2π) * Δϕ) : nothing
        isodd(facets) ? facets = 2 * div(facets, 2) : nothing
        facets < 8 ? facets = 8 : nothing
        nbf = Int(facets / 2)            # Number of faces
        nbv = issector ? nbf + 1 : nbf   # Number of vertices
        nbc = ishollow ? nbv : 1         # Number of centers
        z = z
        range = 1:(2*nbv + 2*nbc)
        function inner(i)
            return if i <= 2*nbv
                ϕ = ϕ₀ + (Δϕ * (((i + 1) ÷ 2) - 1)) / nbf
                up = ifelse(isodd(i), z, -z)
                Point(rmax * cos(ϕ), rmax * sin(ϕ), up)
            elseif ishollow
                ϕ = ϕ₀ + (Δϕ * (((i - 2 * nbv + 1) ÷ 2) - 1)) / nbf
                up = ifelse(isodd(i), z, -z)
                Point(rmin * cos(ϕ), rmin * sin(ϕ), up)
            elseif i == length(range)
                Point(0., 0., -z)
            elseif i == length(range) - 1
                Point(0., 0., z)
            end
        end
        return (inner(i) for i in range)
      end
      
      function GeometryBasics.faces(tub::G4Tubs, facets=36)
        rmin = GetInnerRadius(tub)
        Δϕ    = GetDeltaPhiAngle(tub)
        issector = Δϕ < 2π
        ishollow = rmin > 0
        issector ?  facets =  round(Int64, (facets/2π) * Δϕ) : nothing
        isodd(facets) ? facets = 2 * div(facets, 2) : nothing
        facets < 8 ? facets = 8 : nothing
        nbf = Int(facets / 2)            # Number of faces
        nbv = issector ? nbf + 1 : nbf   # Number of vertices
        nbc = ishollow ? nbv : 1         # Number of centers
        indexes = Vector{QuadFace{Int64}}()
        for j in 1:nbf
            a,b = 2j-1, 2j
            c,d = !issector && j == nbf ? (1, 2) : (2j+1, 2j+2) 
            push!(indexes, (a,b,d,c))
            if ishollow
                a′,b′ = 2j-1+2nbv, 2j+2nbv
                c′,d′ = !issector && j == nbf ? (2nbv+1, 2nbv+2) : (2j+1+2nbv, 2j+2+2nbv)
                # inner wall
                push!(indexes, (a′,b′,d′,c′))
                # top
                push!(indexes, (c, c′, a′, a))
                # bottom
                push!(indexes, (b, b′, d′, d))
            else
                a′,b′ = 2nbv+1, 2nbv+2
                # top
                push!(indexes, (a′,a, c, c))
                # bottom
                push!(indexes, (b′,d, b, b))
            end
        end
        if issector
            # wedge walls
            a, b, c, d  = ( 1, 2, 2nbv-1, 2nbv)
            a′,b′,c′,d′ = ishollow ? (2nbv+1, 2nbv+2, 4nbv-1, 4nbv ) : (2nbv+1, 2nbv+2, 2nbv+1, 2nbv+2)
            push!(indexes, (a,  b, b′, a′))
            push!(indexes, (c′, d′, d, c ))
        end
        return indexes
    end
    
    function GeometryBasics.normals(tub::G4Tubs, facets=36)
        rmin = GetInnerRadius(tub)
        Δϕ    = GetDeltaPhiAngle(tub)
        issector = Δϕ < 2π
        ishollow = rmin > 0
        issector ?  facets =  round(Int64, (facets/2π) * Δϕ) : nothing
        isodd(facets) ? facets = 2 * div(facets, 2) : nothing
        facets < 8 ? facets = 8 : nothing
        nbf = Int(facets / 2)            # Number of faces
        nbv = issector ? nbf + 1 : nbf   # Number of vertices
        nbc = ishollow ? nbv : 1         # Number of centers
        range = 1:(2*nbv + 2*nbc)
        function inner(i)
            return if i <= 2*nbv
                ϕ = ϕ₀ + (Δϕ * (((i + 1) ÷ 2) - 1)) / nbf
                up = ifelse(isodd(i), 1/√2, -1/√2)
                Vector3(cos(ϕ)/√2, sin(ϕ)/√2, up)
            elseif ishollow
                ϕ = ϕ₀ + (Δϕ * (((i + 1) ÷ 2) - 1)) / nbf
                up = ifelse(isodd(i), 1/√2, -1/√2)
                Vector3(-cos(ϕ)/√2, -sin(ϕ)/√2, up)
            elseif i == length(range)
                Vector3(0., 0., -1.)
            elseif i == length(range) - 1
                Vector3(0., 0., 1.)
            end
        end
        return (inner(i) for i in range)
    end
    

end # module G4Visualization
