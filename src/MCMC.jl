"""
    MCMC

To construct a simple MCMC object which, given a prior distribution,
will update in a Metropolis-Hastings fashion with respect to a quadratic
likelihood. It also computes acceptance ratios
"""
module MCMC

using ..EKI
using ..Truth
using ..GPEmulator

const T = GPEmulator.GPObj
const pred = GPEmulator.predict

# packages
using Statistics
using Distributions
using LinearAlgebra

# exports
export MCMCObj
export mcmc_sample!
export accept_ratio
export reset_with_step!
export get_posterior
export find_mcmc_step!
export sample_posterior!


#####
##### Structure definitions
#####

# structure to organize MCMC parameters and data
struct MCMCObj{FT<:AbstractFloat,I<:Int}
    truth_sample::Vector{FT}
    truth_cov::Array{FT, 2}
    truth_covinv::Array{FT, 2}
    prior::Array
    step::Array{FT}
    burnin::I
    param::Vector{FT}
    posterior::Array{FT, 2}
    log_posterior::Array{Union{FT,Nothing}}
    iter::Array{I}
    accept::Array{I}
    algtype::String
    standardized::Bool
end


#####
##### Function definitions
#####

#outer constructors
function MCMCObj(truth_sample::Vector{FT}, truth_cov::Array{FT, 2},
                 priors::Array, step::FT, param_init::Vector{FT},
                 max_iter::I, algtype::String, burnin::I,
                 standardized::Bool) where {FT<:AbstractFloat,I<:Int}

    # first row is param_init
    posterior = zeros(max_iter + 1, length(param_init))
    posterior[1, :] = param_init
    param = param_init
    log_posterior = [nothing]
    iter = [1]
    truth_covinv = inv(truth_cov)
    accept = [0]
    if algtype != "rwm"
        println("only random walk metropolis 'rwm' is implemented so far")
        sys.exit()
    end
    MCMCObj{FT,I}(truth_sample, truth_cov, truth_covinv, priors, [step], burnin,
            param, posterior, log_posterior, iter, accept, algtype,
            standardized)

end

function reset_with_step!(mcmc::MCMCObj{FT}, step::FT) where {FT}
    # reset to beginning with new stepsize
    mcmc.step[1] = step
    mcmc.log_posterior[1] = nothing
    mcmc.iter[1] = 1
    mcmc.accept[1] = 0
    mcmc.posterior[2:end, :] = zeros(size(mcmc.posterior[2:end, :]))
    mcmc.param[:] = mcmc.posterior[1, :]
end


function get_posterior(mcmc::MCMCObj)
    return mcmc.posterior[mcmc.burnin+1:end, :]
end

function mcmc_sample!(mcmc::MCMCObj{FT}, g::Vector{FT}, gvar::Vector{FT}) where {FT}
    if mcmc.algtype == "rwm"
        log_posterior = log_likelihood(mcmc, g, gvar) + log_prior(mcmc)
    end

    if mcmc.log_posterior[1] isa Nothing #do an accept step.
        mcmc.log_posterior[1] = log_posterior - log(0.5) #this makes p_accept = 0.5
    end
    p_accept = exp(log_posterior - mcmc.log_posterior[1])

    if p_accept > rand(Distributions.Uniform(0, 1))
        mcmc.posterior[1 + mcmc.iter[1], :] = mcmc.param
        mcmc.log_posterior[1] = log_posterior
        mcmc.accept[1] = mcmc.accept[1] + 1
    else
        mcmc.posterior[1 + mcmc.iter[1], :] = mcmc.posterior[mcmc.iter[1], :]
    end
    # get new parameters by comparing likelihood_current * prior_current to
    # likelihood_proposal * prior_proposal - either we accept the proposed
    # parameter or we stay where we are.
    mcmc.param[:] = proposal(mcmc)[:]
    mcmc.iter[1] = mcmc.iter[1] + 1

end

function accept_ratio(mcmc::MCMCObj{FT}) where {FT}
    return convert(FT, mcmc.accept[1]) / mcmc.iter[1]
end


function log_likelihood(mcmc::MCMCObj{FT},
                        g::Vector{FT},
                        gvar::Vector{FT}) where {FT}
    log_rho = [0.0]
    if gvar == nothing
        diff = g - mcmc.truth_sample
        log_rho[1] = -0.5 * diff' * mcmc.truth_covinv * diff
    else
      total_cov = Diagonal(gvar) .+ mcmc.truth_cov
      total_cov_inv = inv(total_cov)
      diff = g - mcmc.truth_sample
      log_rho[1] = -0.5 * diff' * total_cov_inv * diff - 0.5 * log(det(total_cov))
    end
    return log_rho[1]
end


function log_prior(mcmc::MCMCObj)
    log_rho = [0.0]
    # Assume independent priors for each parameter
    priors = mcmc.prior
    for (param, prior_dist) in zip(mcmc.param, priors)
        if mcmc.standardized
            param_std = std(prior_dist)
            param_mean = mean(prior_dist)
            log_rho[1] += logpdf(prior_dist, param*param_std + param_mean) # get density at current parameter value
        else
            log_rho[1] += logpdf(prior_dist, param) # get density at current parameter value
        end
    end

    return log_rho[1]
end


function proposal(mcmc::MCMCObj)

    variances = ones(length(mcmc.param))
#    for (idx, prior) in enumerate(mcmc.prior)
#        variances[idx] = var(prior)
#    end

    if mcmc.algtype == "rwm"
        #prop_dist = MvNormal(mcmc.posterior[1 + mcmc.iter[1], :], (mcmc.step[1]) * Diagonal(variances))
        prop_dist = MvNormal(zeros(length(mcmc.param)), (mcmc.step[1]^2) * Diagonal(variances))
    end
    sample = mcmc.posterior[1 + mcmc.iter[1], :] .+ rand(prop_dist)

#    for (idx, prior) in enumerate(mcmc.prior)
#        while !insupport(prior, sample[idx])
#            println("not in support - resampling")
#            sample[:] = mcmc.posterior[1 + mcmc.iter[1], :] .+ rand(prop_dist)
#        end
#    end

    return sample
end


function find_mcmc_step!(mcmc_test::MCMCObj{FT}, gpobj::T) where {FT}
    step = mcmc_test.step[1]
    mcmc_accept = false
    doubled = false
    halved = false
    countmcmc = 0

    println("Begin step size search")
    println("iteration 0; current parameters ", mcmc_test.param')
    flush(stdout)
    it = 0
    local acc_ratio
    while mcmc_accept == false

        param = convert(Array{FT, 2}, mcmc_test.param')
        # test predictions param' is 1xN_params
        gp_pred, gp_predvar = pred(gpobj, param)
        gp_pred = cat(gp_pred..., dims=2)
        gp_predvar = cat(gp_predvar..., dims=2)

        mcmc_sample!(mcmc_test, vec(gp_pred), vec(gp_predvar))
        it += 1
        if it % 2000 == 0
            countmcmc += 1
            acc_ratio = accept_ratio(mcmc_test)
            println("iteration ", it, "; acceptance rate = ", acc_ratio,
                    ", current parameters ", param)
            flush(stdout)
            if countmcmc == 20
                println("failed to choose suitable stepsize in ", countmcmc,
                        "iterations")
                exit()
            end
            it = 0
            if doubled && halved
                step *= 0.75
                reset_with_step!(mcmc_test, step)
                doubled = false
                halved = false
            elseif acc_ratio < 0.15
                step *= 0.5
                reset_with_step!(mcmc_test, step)
                halved = true
            elseif acc_ratio>0.35
                step *= 2.0
                reset_with_step!(mcmc_test, step)
                doubled = true
            else
                mcmc_accept = true
            end
            if mcmc_accept == false
                println("new step size: ", step)
                flush(stdout)
            end
        end

    end

    return mcmc_test.step[1], acc_ratio
end


function sample_posterior!(mcmc::MCMCObj{FT}, gpobj::T, max_iter::I) where {FT,I,T}

    println("iteration 0; current parameters ", mcmc.param')
    flush(stdout)

    for mcmcit in 1:max_iter
        param = convert(Array{FT, 2}, mcmc.param')
        # test predictions param' is 1xN_params
        gp_pred, gp_predvar = pred(gpobj, param)
        gp_pred = cat(gp_pred..., dims=2)
        gp_predvar = cat(gp_predvar..., dims=2)

        mcmc_sample!(mcmc, vec(gp_pred), vec(gp_predvar))

        if mcmcit % 1000 == 0
            acc_ratio = accept_ratio(mcmc)
            # TODO: Add callbacks, remove print statements
            println("iteration ", mcmcit ," of ", max_iter,
                    "; acceptance rate = ", acc_ratio,
                    ", current parameters ", param)
            flush(stdout)
        end
    end
end

end # module MCMC
