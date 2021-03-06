using Test
using CalibrateEmulateSample
using LinearAlgebra, Distributions

@testset "EKS" begin

    for FT in [Float32, Float64]
        Σ = 100.0^2*Matrix{FT}(I,2,2)
        μ = [3.0,5.0]
        prior = MvNormal(μ, Σ)

        A = hcat(ones(10), [i == 1 ? 1.0 : 0.0 for i = 1:10])
        f(x) = A*x

        u_star = [-1.0,2.0]
        y_obs = A*u_star

        Γ = 0.1*Matrix{FT}(I,10,10)

        prob = CalibrateEmulateSample.CESProblem(prior, f, y_obs, CalibrateEmulateSample.CovarianceSpace(Γ))

        J = 50
        θs = [rand(2) for i in 1:J]

        for i = 1:20
            fθs = map(f, θs)
            θs = CalibrateEmulateSample.eks_iter(prob, θs, fθs)
        end

        postΣ = inv(inv(Σ) + A'*inv(Γ)*A)
        postμ = postΣ*(inv(Σ)*μ + A'*inv(Γ)*y_obs)


        @test mean(θs) ≈ postμ atol=2e-1
        @test cov(θs) ≈ postΣ atol=5e-1
    end
end
