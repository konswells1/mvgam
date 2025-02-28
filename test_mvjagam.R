#### Testing the mvjagam function ####
# Utility functions, too specific to put into the package but useful for our study
plot_mvgam_season = function(out_gam_mod, series, data_test, data_train,
                             xlab = 'Season'){

  pred_dat <- expand.grid(series = levels(data_train$series)[series],
                          season = seq(min(data_train$season),
                                       max(data_train$season), length.out = 100),
                          year = mean(data_train$year),
                          cum_gdd = mean(data_train$cum_gdd, na.rm = T),
                          siteID = as.character(unique(data_train$siteID[which(data_train$series ==
                                                                                 levels(data_train$series)[series])])))
  Xp <- predict(out_gam_mod$mgcv_model, newdata = pred_dat, type = 'lpmatrix')
  betas <- MCMCchains(out_gam_mod$jags_output, 'b')
  plot(Xp %*% betas[1,] ~ pred_dat$season, ylim = range(Xp %*% betas[1,] + 1.5,
                                                        Xp %*% betas[1,] - 1.5),

       col = rgb(150, 0, 0, max = 255, alpha = 10), type = 'l',
       ylab = paste0('F(season) for ', levels(data_train$series)[series]),
       xlab = xlab)
  for(i in 2:1000){
    lines(Xp %*% betas[i,] ~ pred_dat$season,

          col = rgb(150, 0, 0, max = 255, alpha = 10))
  }
}

plot_mvgam_gdd = function(out_gam_mod, series, data_test, data_train,
                          mean_gdd, sd_gdd,
                          xlab = 'Season'){

  pred_dat <- expand.grid(series = levels(data_train$series)[series],
                          season = 20,
                          in_season = 1,
                          year = mean(data_train$year),
                          cum_gdd = seq(min(data_train$cum_gdd[which(data_train$series ==
                                                                       levels(data_train$series)[series])],
                                            na.rm = T),
                                        max(data_train$cum_gdd[which(data_train$series ==
                                                                       levels(data_train$series)[series])],
                                            na.rm = T), length.out = 100),
                          siteID = as.character(unique(data_train$siteID[which(data_train$series ==
                                                                                 levels(data_train$series)[series])])))
  Xp <- predict(out_gam_mod$mgcv_model, newdata = pred_dat, type = 'lpmatrix')
  betas <- MCMCchains(out_gam_mod$jags_output, 'b')
  preds <- matrix(NA, nrow = 1000, ncol = length(pred_dat$cum_gdd))
  for(i in 1:1000){
    preds[i,] <- rnbinom(length(pred_dat$cum_gdd), mu = exp(Xp %*% betas[i,]),
                         size = MCMCvis::MCMCsummary(out_gam_mod$jags_output, 'r')$mean)
  }
  int <- apply(preds,
               2, hpd, 0.95)
  preds_last <- preds[1,]
  covar_vals <- (pred_dat$cum_gdd * sd_gdd) + mean_gdd
  plot(preds_last ~ covar_vals,
       type = 'l', ylim = c(0, max(int) + 2),
       col = rgb(1,0,0, alpha = 0),
       ylab = paste0('Predicted peak count for ', levels(data_train$series)[series]),
       xlab = 'Cumulative growing degree days')
  int[int<0] <- 0
  polygon(c(covar_vals, rev(covar_vals)),
          c(int[1,],rev(int[3,])),
          col = rgb(150, 0, 0, max = 255, alpha = 100), border = NA)
  int <- apply(preds,
               2, hpd, 0.68)
  int[int<0] <- 0
  polygon(c(covar_vals, rev(covar_vals)),
          c(int[1,],rev(int[3,])),
          col = rgb(150, 0, 0, max = 255, alpha = 180), border = NA)
  lines(int[2,] ~ covar_vals, col = rgb(150, 0, 0, max = 255), lwd = 2, lty = 'dashed')

  rug(((data_train$cum_gdd * sd_gdd) + mean_gdd)[which(data_train$series ==
                                 levels(data_train$series)[series])])
}

#### NEON mv_gam ####
library(mvgam)
library(dplyr)
data("all_neon_tick_data")

# Prep data for modelling
species = 'Ambloyomma_americanum'

if(species == 'Ambloyomma_americanum'){

  plotIDs <- c('SCBI_013', 'SERC_001', 'SERC_005', 'SERC_006',
               'SERC_002', 'SERC_012', 'KONZ_025', 'UKFS_001',
               'UKFS_004', 'UKFS_003', 'ORNL_002', 'ORNL_040',
               'ORNL_008', 'ORNL_007', 'ORNL_009', 'ORNL_003',
               'TALL_001', 'TALL_008', 'TALL_002')
  model_dat <- all_neon_tick_data %>%
    dplyr::mutate(target = amblyomma_americanum) %>%
    dplyr::select(Year, epiWeek, plotID, target) %>%
    dplyr::mutate(epiWeek = as.numeric(epiWeek)) %>%
    dplyr::filter(Year > 2014 & Year < 2021) %>%
    dplyr::mutate(Year_orig = Year)

  model_dat %>%
    dplyr::full_join(expand.grid(plotID = unique(model_dat$plotID),
                                 Year_orig = unique(model_dat$Year_orig),
                                 epiWeek = seq(1, 52))) %>%
    dplyr::left_join(all_neon_tick_data %>%
                       dplyr::select(siteID, plotID) %>%
                       dplyr::distinct()) %>%
    # Remove winter tick abundances as we are not interested in modelling them
    dplyr::filter(epiWeek > 14) %>%
    dplyr::filter(epiWeek < 41) %>%
    dplyr::mutate(series = plotID,
                  season = epiWeek - 14,
                  year = as.vector(scale(Year_orig)),
                  y = target) %>%
    dplyr::select(-Year, -epiWeek, -target) %>%
    dplyr::ungroup() %>%
    dplyr::arrange(Year_orig, season, series) -> model_dat

  model_dat %>%
    dplyr::left_join(all_neon_tick_data %>%
                       dplyr::ungroup() %>%
                       dplyr::select(Year, siteID, cum_sdd, cum_gdd) %>%
                       dplyr::mutate(Year_orig = Year) %>%
                       dplyr::select(-Year) %>%
                       dplyr::distinct()) -> model_dat
}


model_dat = model_dat %>%
  # Set indicator for whether time point is 'in-season' or not (trends won't contribute during
  # off season, as counts generally go to zero during this time)
  dplyr::mutate(in_season = ifelse(season >=3 & season <= 22, 1, 0)) %>%
  # Only include a small set of sites for now (11 series in total from three sites)
  dplyr::filter(siteID %in% c('SERC', 'TALL', 'UKFS'),
                Year_orig <= 2019) %>%
  # ID variables need to be factors for JAGS modelling
  dplyr::mutate(plotID = factor(plotID),
                siteID = factor(siteID),
                series = factor(series))

# Scale the environmental covariate and store the mean and sd for later plotting
sd_gdd <- sd(model_dat$cum_gdd)
mean_gdd <- mean(model_dat$cum_gdd)
model_dat$cum_gdd <- (model_dat$cum_gdd - mean_gdd) / sd_gdd

# Split into training and testing
data_train = model_dat[1:(floor(nrow(model_dat) * 0.9)),]
data_test = model_dat[((floor(nrow(model_dat) * 0.9)) + 1):nrow(model_dat),]
(nrow(data_train) + nrow(data_test)) == nrow(model_dat)

# Hypothesis testing
# NULL. There is no seasonal pattern to be estimated, and we simply let the latent
# factors and site-level effects of growing days influence the series dynamics
null_hyp = y ~ siteID + s(cum_gdd, by = siteID, k = 3) - 1

# 1. Do all series share same seasonal pattern, with any remaining variation due to
# non-seasonal local variation captured by the trends?
hyp1 = y ~
  siteID +
  s(cum_gdd, by = siteID, k = 3) +
  # Global cyclic seasonality term (smooth)
  s(season, k = 12, m = 2, bs = 'cc') - 1

# 2. Do all series share same seasonal pattern but with different magnitudes
# (i.e. random intercepts per series)?
hyp2 = y ~
  siteID +
  s(cum_gdd, by = siteID, k = 3) +
  s(season, k = 12, m = 2, bs = 'cc') +
  # Hierarchical variable intercepts
  s(series, bs = 're') - 1

# 3. Is there evidence for global seasonality but each site's seasonal pattern deviates
# based on more local conditions?
hyp3 = y ~
  siteID +
  s(cum_gdd, by = siteID, k = 3) +
  s(season, k = 4, m = 2, bs = 'cc') +
  s(series, bs = 're') +
  # Site-level deviations from global pattern, which can be wiggly (m=1 to reduce concurvity);
  # If these dominate, they will have smaller smoothing parameters and the global seasonality
  # will become less important (larger smoothing parameter). Sites with the smallest smooth
  # parameters are those that deviate the most from the global seasonality
  s(season, by = siteID, m = 1, k = 8) - 1

# 4. Is there evidence for global seasonality but each plot's seasonal pattern deviates
# based on even more local conditions than above (i.e. plot-level is not as informative)?
# If evidence of gdd effects, can also let use a global smoother and then site-level
# deviations for a 'hierarchical' setup
hyp4 = y ~
  siteID +
  s(cum_gdd, by = siteID, k = 3) +
  s(season, k = 4, m = 2, bs = 'cc') +
  s(series, bs = 're') +
  # Series-level deviations from global pattern
  s(season, by = series, m = 1, k = 8) - 1

# Additional parameters for the model
use_mv <- T

# First simulate from the model's prior distributions
out_gam_sim <- mvjagam(formula = hyp1,
                       data_train = data_train,
                       data_test = data_test,
                       prior_simulation = TRUE,
                       n.adapt = 1000,
                       n.burnin = 1000,
                       n.iter = 1000,
                       thin = 2,
                       use_mv = use_mv,
                       use_nb = FALSE,
                       # Laplace distribution emphasizes our prior that smooths should not be overly wiggly
                       # unless the data supports this
                       rho_prior = 'ddexp(5, 0.2)T(-12, 12)',
                       # Prior is that latent trends should have positive autocorrelation
                       phi_prior = 'dbeta(2,2)',
                       tau_prior = 'dunif(0.1, 100)')

# Now condition the model on the observed data
out_gam_mod <- mvjagam(formula = hyp1,
                        data_train = data_train,
                        data_test = data_test,
                        n.adapt = 1000,
                        n.burnin = 5000,
                        n.iter = 5000,
                        thin = 10,
                        # auto_update attempts to update until some reasonable convergence, but can
                        # be slow!!
                        auto_update = FALSE,
                        use_mv = use_mv,
                        use_nb = FALSE,
                        # Laplace distribution emphasizes prior that smooths should not be overly wiggly
                        # unless the data supports this
                        rho_prior = 'ddexp(5, 0.2)T(-12, 12)',
                        # Prior is that latent trends should have positive autocorrelation
                        phi_prior = 'dbeta(2, 2)',
                        tau_prior = 'dunif(0.1, 100)')

# View the modified JAGS model file
writeLines(out_gam_mod$model_file)

# Summary of key parameters
library(MCMCvis)
MCMCvis::MCMCsummary(out_gam_mod$jags_output, c('phi', 'rho'))

# Traces of key parameters, with prior distributions overlain to investigate
# how informative the data are for each parameter of interest
# Negative binomial size parameter (set to 10,000 if use_nb = FALSE)
MCMCtrace(out_gam_mod$jags_output, params = c('r'),
          pdf = F,
          n.eff = TRUE,
          Rhat = TRUE,
          priors = MCMCvis::MCMCchains(out_gam_sim$jags_output, 'r'),
          post_zm = FALSE)

# Penalties of smooth components (smaller means an effect is more nonlinear)
out_gam_mod$smooth_param_details # rhos are the logged versions of the lambdas
MCMCtrace(out_gam_mod$jags_output, c('rho'),
          pdf = F,
          n.eff = TRUE,
          Rhat = TRUE,
          priors = MCMCvis::MCMCchains(out_gam_sim$jags_output, 'rho'),
          post_zm = FALSE)

# AR1 persistence coefficients for latent dynamic factors (or for each
# individual series if use_mv = FALSE)
MCMCtrace(out_gam_mod$jags_output, c('phi'),
          pdf = F,
          n.eff = TRUE,
          Rhat = TRUE,
          priors = MCMCvis::MCMCchains(out_gam_sim$jags_output, 'phi'),
          post_zm = FALSE)

# Precision for latent dynamic factors (if using latent factors)
MCMCtrace(out_gam_mod$jags_output, c('tau_fac'),
          pdf = F,
          n.eff = TRUE,
          Rhat = TRUE,
          priors = MCMCvis::MCMCchains(out_gam_sim$jags_output, 'tau_fac'),
          post_zm = T)

# Precision for latent trends (if using independent Gaussian trends)
MCMCtrace(out_gam_mod$jags_output, c('tau'),
          pdf = F,
          n.eff = TRUE,
          Rhat = TRUE,
          priors = MCMCvis::MCMCchains(out_gam_sim$jags_output, 'tau'),
          post_zm = FALSE)
dev.off()

if(use_mv){
  if(length(unique(data_train$series)) > 5){
    # Calculate the correlation matrix from the latent variables
    samps <- jags.samples(out_gam_mod$jags_model,
                          variable.names = 'lv_coefs',
                          n.iter = 1000, thin = 1)
    lv_coefs <- samps$lv_coefs
    n_series <- dim(lv_coefs)[1]
    n_lv <- dim(lv_coefs)[2]
    n_samples <- prod(dim(lv_coefs)[3:4])

    # Get arrat of latend variable loadings
    coef_array <- array(NA, dim = c(n_series, n_lv, n_samples))
    for(i in 1:n_series){
      for(j in 1:n_lv){
        coef_array[i, j, ] <- c(lv_coefs[i, j, , 1],
                                lv_coefs[i, j, , 2])
      }
    }

    # Variances of each series' latent trend are fixed at (1/100)^2
    eps_res <- rep((1/100)^2, n_series)

    # Posterior correlations based on latent variable loadings
    correlations <- array(NA, dim = c(n_series, n_series, n_samples))
    for(i in 1:n_samples){
      correlations[,,i] <- cov2cor(tcrossprod(coef_array[,,i]) + diag(eps_res))
    }
    mean_correlations <- apply(correlations, c(1,2), function(x) quantile(x, 0.5))

    # Plot the mean posterior correlations
    mean_correlations[upper.tri(mean_correlations)] <- NA
    mean_correlations <- data.frame(mean_correlations)
    rownames(mean_correlations) <- colnames(mean_correlations) <- levels(data_train$series)

    library(ggplot2)
    ggplot(mean_correlations %>%
             tibble::rownames_to_column("series1") %>%
             tidyr::pivot_longer(-c(series1), names_to = "series2", values_to = "Correlation"),
           aes(x = series1, y = series2)) + geom_tile(aes(fill = Correlation)) +
      scale_fill_gradient2(low="darkred", mid="white", high="darkblue",
                           midpoint = 0,
                           breaks = seq(-1,1,length.out = 5),
                           limits = c(-1, 1),
                           name = 'Residual\ncorrelation') + labs(x = '', y = '') + theme_dark() +
      theme(axis.text.x = element_text(angle = 45, hjust=1))

  }
}

#### If GAM component is LESS supported, we should see evidence in the form of: ####
# 1. Poorer convergence of smoothing parameter estimates, suggesting the model
# is more 'mis-specified' and harder to fit

# 2. Stronger residual correlations, suggesting we are missing some site-level structure
summary(as.vector(as.matrix(mean_correlations)))

# 3. Smaller precisions for tau_fac (i.e. larger variance for latent dynamic factors)
MCMCsummary(out_gam_mod$jags_output, 'tau_fac')

# 4. Visual evidence of seasonality in latent trends
# Total number of series in the set
length(unique(data_train$series))
series = 4
opar <- par()
par(mfrow = c(3, 1))
# Plot the estimated seasonality function
plot_mvgam_season(out_gam_mod, series = series, data_test = data_test,
                  data_train = data_train, xlab = 'Epidemiological week')
# Plot the posterior predictions for the training and testing sets
plot_mvgam_fc(out_gam_mod, series = series, data_test = data_test,
              data_train = data_train)
# Plot the estimated latent trend component
plot_mvgam_trend(out_gam_mod, series = series, data_test = data_test,
                 data_train = data_train)
par(opar)

#### Other aspects to investigate ####
# Plot the estimated cumulative growing degree days function, with a rug at the bottom
# to show the observed values of the covariate for this particular series
plot_mvgam_gdd(out_gam_mod, series = series, data_test = data_test,
               mean_gdd = mean_gdd, sd_gdd = sd_gdd,
               data_train = data_train, xlab = 'Epidemiological week')

# Need to calculate discrete rank probability score for out of sample forecasts from each model

# Consider adding an AR(frequency) term so that current trend also depends on the trend's value from one year
# ago (i.e. here we have frequency 26, so we could have an AR(1, 26) model for the trend)
