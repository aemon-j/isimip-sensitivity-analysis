setwd(dirname(rstudioapi::getSourceEditorContext()$path))

# clean up
rm(list=ls())
graphics.off()
cat("\14")

library(tidyverse)
library(grid)
library(gridExtra)
library(ggExtra)
library(ggdendro)
library(cluster)
library(ggplot2)
library(ggpubr)
library(knitr)
library(nnet)
library(data.table)

# the results from the calibration runs descriptions of the different columns
# can be found in "data/results_lhc_description.csv"
res <- read.csv("data/results_lhc.csv")
# meta information about the lakes 
lake_meta <- readRDS("data_derived/lake_meta_data_derived.RDS")
lake_meta_desc <- readRDS("data_derived/lake_meta_desc_derived.RDS")

# data frame with all metrics for single best model per lake
best_all_a <- readRDS("data_derived/single_best_model.RDS")

# data frame with all metrics for best set per lake and per model
best_all <- readRDS("data_derived/best_par_sets.RDS")

# ggplot theme to be used
thm <- theme_pubr(base_size = 16) + grids()

##---------- look at best performing model per lake and metric -----------------

# calculate fraction of lakes for which each model performs best across the
# different metrics

count_best <- res |> group_by(lake) |>
  reframe(rmse = model[which.min(rmse)],
          nse = model[which.max(nse)],
          r = model[which.max(r)],
          bias = model[which.min(abs(bias))],
          mae = model[which.min(mae)],
          nmae = model[which.min(nmae)]) |>
  pivot_longer(-1) |> group_by(value, name) |>
  reframe(n = round(n()/73, 3)*100) |>
  rename(Metric = "name", Model = "value") |>
  pivot_wider(id_cols = "Model", names_from = "Metric", values_from = "n") |>
  setNames(c("Model", "bias", "mae", "nmae",
             "NSE", "r", "RMSE"))

# create a table that can be copy and pasted into the quarto document
kable(count_best, format = "pipe")

# look at the distribution of number of different best performing models over the
# different metrics

res |> group_by(lake) |>
  reframe(rmse = model[which.min(rmse)],
          nse = model[which.max(nse)],
          r = model[which.max(r)],
          bias = model[which.min(abs(bias))],
          mae = model[which.min(mae)],
          nmae = model[which.min(nmae)]) |>
  pivot_longer(-1) |> group_by(lake) |> reframe(n = length(unique(value))) |>
  ggplot() + geom_histogram(aes(x = n))



##--------------- statistical models for best model/performacne ----------------
# fit multinomial log-linear model 
dat <- best_all_a |> filter(best_met == "rmse") |> left_join(lake_meta) |>
  mutate(model = factor(model, model, model),
         Reservoir.or.lake. = factor(Reservoir.or.lake.,
         Reservoir.or.lake.,
         Reservoir.or.lake.)) |> ungroup()

dat$model <- relevel(dat$model, ref = "Simstrat")
test <- multinom(model ~ kw + elevation.m + max.depth.m +
                   lake.area.sqkm + latitude.dec.deg + longitude.dec.deg + crv,
                 data = dat)
summary(test)
exp(coef(test))

pdat <- expand_grid(kw = seq(min(dat$kw), max(dat$kw), length.out = 5),
                    #kw = median(dat$kw),
                    elevation.m = mean(dat$elevation.m),
                    #max.depth.m = seq(min(dat$max.depth.m),
                    #                  max(dat$max.depth.m), length.out = 20),
                    max.depth.m = median(dat$max.depth.m),
                    #lake.area.sqkm = mean(dat$lake.area.sqkm),
                    lake.area.sqkm = seq(min(dat$lake.area.sqkm),
                                         max(dat$lake.area.sqkm),
                                         length.out = 20),
                    latitude.dec.deg = mean(dat$latitude.dec.deg),
                    longitude.dec.deg = mean(dat$longitude.dec.deg),
                    crv = levels(dat$crv))
  

res_m <- predict(test, newdata = pdat, "probs")
res_m <- cbind(res_m, pdat) |> pivot_longer(1:4)

res_m |> ggplot() + geom_line(aes(x = lake.area.sqkm, y = value, col = name)) +
  facet_grid(crv~kw)

## estimate performance metric based upon lake characteristics

ggplot(dat) + geom_point(aes(x = kw, y = lake.area.sqkm, col = model, pch = crv)) +
  scale_y_log10() + scale_x_log10()


## model best rsme from lake propertiers

rmse_m <- best_all_a |> filter(best_met == "rmse") |>left_join(lake_meta) |>
  lm(formula = rmse ~ (kw + elevation.m + max.depth.m +
               lake.area.sqkm + latitude.dec.deg + longitude.dec.deg +
               reldepth_median + months_meas + osgood) * crv)

rmse_m_step <- step(rmse_m)

summary(rmse_m)
summary(rmse_m_step)

##--------------- plots looking at the best performing parameter set -------------


# distribution of the single best model per lake for all 6 metrics
p_dist_lake_a <- best_all_a |> pivot_longer(4:9) |> filter(best_met == name) |>
  ggplot() +
  geom_histogram(aes(x = value, y = ..count..),
                 bins = 20, col = 1) +
  thm + xlab("") +
  facet_wrap(~best_met, scales = "free")

ggsave("Plots/best_fit.pdf", p_dist_lake_a, width = 13, height = 7)

# a map of the lakes with the location color coded according to the best
# performing model
world <- map_data("world")
best_all |> filter(best_met == "rmse") |> left_join(lake_meta) |>
  group_by(lake) |> slice(which.min(rmse)) |> ggplot() +
  geom_map(
    data = world, map = world, fill = "grey33",
    aes(map_id = region)
  ) +
  geom_point(aes(y = latitude.dec.deg, x = longitude.dec.deg, col = model),
             size = 2, position = "jitter") + ylim(-40, 70) +
  xlim(-150, 180) + theme_void()

# a map of the lakes with the location color coded according to the lowest
# rmse from all four models
best_all |> filter(best_met == "rmse") |> left_join(lake_meta) |>
  group_by(lake) |> slice(which.min(rmse)) |> ggplot() +
  geom_map(
    data = world, map = world, fill = "grey33",
    aes(map_id = region)
  ) +
  geom_point(aes(y = latitude.dec.deg, x = longitude.dec.deg, col = rmse),
             size = 2, position = "jitter") + ylim(-90, 90) +
  xlim(-180, 180) + xlab("Longitude") + ylab("Latitude") +
  theme_pubclean(base_size = 17) + scale_color_viridis_c("RMSE (K)",option = "C")


## function that plots relating min RMSE to lake characteristics
plot_meta <- function(data, measure = "rmse") {
  p_meta1 <- ggplot(data) + geom_point(aes_string(x = "mean.depth.m", y = measure, col = "model")) +
    scale_x_log10() + ggtitle("min RMSE vs. mean lake depth") + thm + xlab("Mean lake depth (m)") +
    ylab("RMSE (K)")
  
  p_meta2 <- ggplot(data) + geom_point(aes_string(x = "lake.area.sqkm", y = measure, col = "model")) +
    scale_x_log10() + ggtitle("min RMSE vs. lake area") + thm + xlab("Lake Area (km²)") +
    ylab("RMSE (K)")
  
  p_meta3 <- ggplot(data) + geom_point(aes_string(x = "latitude.dec.deg", y = measure, col = "model")) +
    scale_x_log10() + ggtitle("min RMSE vs.latitude") + thm + xlab("Latitude (°N)") +
    ylab("RMSE (K)")
  
  p_meta4 <- ggplot(data) + geom_point(aes_string(x = "longitude.dec.deg", y = measure, col = "model")) +
    scale_x_log10() + ggtitle("min RMSE vs.longitude") + thm + xlab("Longitude (°E)") +
    ylab("RMSE (K)")
  
  
  p_meta6 <- ggplot(data) + geom_point(aes_string(x = "elevation.m", y = measure, col = "model")) +
    scale_x_log10() + ggtitle("min RMSE vs. elevation") + thm + xlab("Lake elevation (m asl)") +
    ylab("RMSE (K)")
  
  p_meta7 <- ggplot(data) + geom_point(aes_string(x = "kw", y = measure, col = "model")) +
    ggtitle("min RMSE vs. Secchi disk depth") + thm + xlab("Average Kw value (1/m)") +
    ylab("RMSE (K)")
  
  
  p_meta8 <- ggplot(data) + geom_point(aes_string(x = "months_meas", y = measure, col = "model")) +
    ggtitle("min RMSE vs. no. months with obs") + thm + xlab("Months with observations (-)") +
    ylab("RMSE (K)")
  
  
  p_meta10 <- ggplot(data) + geom_point(aes_string(x = "reldepth_median", y = measure, col = "model")) +
    ggtitle("min RMSE vs. relative depth of most obs") + thm + xlab("center of relative depth (-)") +
    ylab("RMSE (K)")
  
  
  p1_meta <- ggarrange(p_meta1,
                       p_meta2,
                       p_meta3,
                       p_meta6,
                       p_meta7,
                       p_meta4,
                       ncol = 3, nrow = 2, common.legend = TRUE)
  
  p2_meta <- ggarrange(p_meta8,
                       p_meta10,
                       ncol = 2, nrow = 2, common.legend = TRUE)
  return(list(p1_meta, p2_meta))
}


# plot meta data vs best r for each lake and model
best_all |> filter(best_met == "r") |> left_join(lake_meta) |> 
  plot_meta(measure = "r")

# same plot but just for the best model per lake
best_all_a |> filter(best_met == "rmse") |> left_join(lake_meta) |>
  plot_meta()


##-------- compare models -----------------------

# distribution of rmse along all 2000 parameter sets and 73 lakes
res |> pivot_longer(4:9) |> ggplot() +
  geom_violin(aes(x = model, y = value, fill = model)) + scale_y_log10() +
  facet_wrap(~name, scales = "free_y") + thm + scale_y_log10()

# check if the same models perform good or bad along the four models
p_mcomp1 <- best_all |> pivot_longer(4:9) |> 
  group_by(lake, best_met, name) |> filter(best_met == name) |>
  reframe(range = diff(range(value)),
          sd = sd(value,),
          min = min(value),
          max = max(value)) |>
  mutate(range = ifelse(range > 1e3, NA, range)) |>
  left_join(lake_meta) |>
  ggplot() + geom_boxplot(aes(y = range, x = kmcluster, fill = kmcluster)) +
  facet_wrap(~name, scales = "free_y") + thm +
  scale_fill_viridis_d("Cluster") + ylab("Range model performacne") +
  xlab("Cluster") + scale_y_log10()

p_mcomp2 <- best_all |> pivot_longer(4:9) |>
  group_by(lake, best_met, name) |> filter(best_met == name) |>
  reframe(range = diff(range(value)),
          sd = sd(value),
          best = case_when(name == "bias" ~ min(abs(value)),
                            name %in% c("mae", "nmae", "rmse") ~ min(value),
                            name %in% c("r", "nse") ~ max(value)),
          worst = case_when(name == "bias" ~ max(abs(value)),
                            name %in% c("mae", "nmae", "rmse") ~ max(value),
                            name %in% c("r", "nse") ~ min(value))) |>
  mutate(best = ifelse(best > 1e3, NA, best),
         worst = ifelse(worst > 1e3, NA, worst)) |>
  left_join(lake_meta) |>
  ggplot() + geom_point(aes(x = worst, y = best, col = kmcluster),
                        size = 3) +
  geom_abline(aes(intercept = 0, slope = 1), col = 2, lty = 17) +
  facet_wrap(~name, scales = "free") + thm +
  scale_color_viridis_d("Cluster") + xlab("Poorest model performance") +
  ylab("Best model performance") + scale_x_log10() + scale_y_log10()

ggarrange(p_mcomp1, p_mcomp2, common.legend = TRUE)
ggsave("Plots/best_worst_model.png", width = 21, height = 10, bg = "white")

##-------- relate calibrated parameter values to lake characteristics ----

# plot relating used wind speed scaling factor (of best rmse set) to lake area
# for each model
best_all_a |> left_join(lake_meta) |>
  ggplot() + geom_point(aes(y = wind_speed,
                            x = lake.area.sqkm,
                            col = model), size = 2) +
  thm + facet_wrap(.~best_met) + scale_x_log10()


##### Plot best parameter values vs lake characteristics
lm <- read.csv("data/Lake_meta.csv")
df_best_rmse = best_all |> filter(best_met == "rmse") |>
  left_join(lm, by = c("lake" = "Lake.Short.Name")) |>data.table()


cal_pars = names(df_best_rmse)[10:24]
lake_chars = names(df_best_rmse)[c(30, 33, 35, 36, 39)]

plts = list()
for(i in lake_chars){
  plts2 = list()
  for(j in cal_pars){
    p = ggplot(df_best_rmse) +
      geom_point(aes(.data[[i]], .data[[j]], colour = model))
    if(i %in% c("mean.depth.m", "lake.area.sqkm")){
      p = p +
        scale_x_continuous(trans = "log10")
    }
    p = p +
      thm
    
    plts2[[length(plts2) + 1]] = p
  }
  
  p_i = ggarrange(plotlist = plts2, common.legend = T, align = "hv")
  
  plts[[length(plts) + 1]] = p_i
}