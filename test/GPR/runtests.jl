using Test
using NPZ
using LinearAlgebra

include(joinpath("..","..","src","GPR.jl"))

const data_dir = joinpath(@__DIR__, "data")
const gpr_data = NPZ.npzread(joinpath(data_dir, "data_points.npy"))
const gpr_mesh = NPZ.npzread(joinpath(data_dir, "mesh.npy"))
const rbf_mean = NPZ.npzread(joinpath(data_dir, "rbf_mean.npy"))
const rbf_std = NPZ.npzread(joinpath(data_dir, "rbf_std.npy"))
const matern_def_mean = NPZ.npzread(joinpath(data_dir, "matern_def_mean.npy"))
const matern_def_std = NPZ.npzread(joinpath(data_dir, "matern_def_std.npy"))
const matern_05_mesh = NPZ.npzread(joinpath(data_dir, "matern_05_mesh.npy"))
const matern_05_mean = NPZ.npzread(joinpath(data_dir, "matern_05_mean.npy"))
const matern_05_std = NPZ.npzread(joinpath(data_dir, "matern_05_std.npy"))

const inf_norm = x -> LinearAlgebra.norm(x, Inf)

X = 0:0.1:1
y = X.^2
xmesh = 0:0.01:1
gprw = GPR.Wrap()

@testset "GPR: structs" begin
  @test !gprw.__data_set
  @test !gprw.__subsample_set
  @test gprw.data == nothing
  @test gprw.subsample == nothing
  @test gprw.GPR == nothing
end

thrsh = gprw.thrsh
@testset "GPR: methods" begin
  ex_thrown1 = false
  try
    GPR.subsample!(gprw)
  catch
    ex_thrown1 = true
  end
  @test ex_thrown1

  ex_thrown2 = false
  try
    GPR.set_data!(gprw, rand(20))
  catch
    ex_thrown2 = true
  end
  @test ex_thrown2

  GPR.set_data!(gprw, rand(20,2,2))
  @test gprw.__data_set
  @test !gprw.__subsample_set
  @test size(gprw.data,1) == 20

  GPR.set_data!(gprw, cat(X,y,dims=2))
  @test gprw.__data_set
  @test !gprw.__subsample_set

  ex_thrown3 = false
  try
    GPR.learn!(gprw)
  catch
    ex_thrown3 = true
  end
  @test !ex_thrown3
  @test gprw.__subsample_set

  GPR.learn!(gprw, kernel = "matern")
  @test occursin(r"matern"i, string(gprw.GPR.kernel))

  GPR.set_data!(gprw, rand(20,2))
  @test !gprw.__subsample_set
  @test gprw.GPR == nothing
  GPR.subsample!(gprw, indices = [1,2,3])
  @test gprw.__subsample_set
  GPR.subsample!(gprw, -1)
  @test size(gprw.subsample,1) == 20
  GPR.subsample!(gprw)
  @test size(gprw.subsample,1) == 20

  GPR.set_data!(gprw, cat(X,y,dims=2))
  GPR.learn!(gprw, noise = 1e-10)
  @test occursin(r"rbf"i, string(gprw.GPR.kernel))

  ytrue = xmesh.^2
  ypred = GPR.predict(gprw, xmesh)
  @test isapprox(ytrue, ypred, atol=1e-4, norm=inf_norm)

  mesh_, mean_, std_ = GPR.mmstd(gprw, mesh_n=101)
  @test isapprox(mesh_, xmesh, atol=1e-8, norm=inf_norm)
  @test isapprox(ypred, mean_, atol=1e-8, norm=inf_norm)

  mean, std = GPR.predict(gprw, xmesh, return_std = true)
  @test isapprox(mean, mean_, atol=1e-8, norm=inf_norm)
  @test isapprox(std, std_, atol=1e-8, norm=inf_norm)
  @test ndims(mean) == 1
  @test ndims(std) == 1
  @test size(std,1) == size(mean,1)
  @test all(std .>= 0)

  @test gprw.thrsh == thrsh
end

GPR.set_data!(gprw, gpr_data)
gprw.thrsh = -1
@testset "GPR: non-synthetic data" begin
  GPR.learn!(gprw)
  mesh, mean, std = GPR.mmstd(gprw)
  @test size(gprw.data,1) == 800
  @test size(gprw.subsample,1) == 800
  @test isapprox(mesh, gpr_mesh, atol=1e-8, norm=inf_norm)
  @test isapprox(mean, rbf_mean, atol=1e-3, norm=inf_norm)
  @test isapprox(std, rbf_std, atol=1e-3, norm=inf_norm)

  GPR.learn!(gprw, kernel = "matern")
  mean, std = GPR.predict(gprw, gpr_mesh, return_std = true)
  @test isapprox(mean, matern_def_mean, atol=1e-3, norm=inf_norm)
  @test isapprox(std, matern_def_std, atol=1e-3, norm=inf_norm)

  GPR.learn!(gprw, kernel = "matern", nu = 0.5)
  mean, std = GPR.predict(gprw, matern_05_mesh, return_std = true)
  @test isapprox(mean, matern_05_mean, atol=1e-3, norm=inf_norm)
  @test isapprox(std, matern_05_std, atol=1e-3, norm=inf_norm)
end
