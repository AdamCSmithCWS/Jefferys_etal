## Fitting the habitat-change model with iCAR trend component to 2006 - 2021 BBS data
setwd("C:/GitHub/Jeffreys_etal") #useful if running in standaolone R session (avoids Rstudio fails)
setwd("C:/Users/SmithAC/Documents/GitHub/Jefferys_etal")

library(tidyverse)
library(cmdstanr)
library(patchwork)
library(sf)
library(ggsn) #scale bars and north arrow




output_dir <- "output"
species <- "Rufous Hummingbird" 


species_f <- gsub(gsub(species,pattern = " ",replacement = "_",fixed = T),pattern = "'",replacement = "",fixed = T)

spp1 <- "habitat"

spp <- paste0("_",spp1,"_")


for(firstYear in c(1985,2006)){
  
  lastYear <- ifelse(firstYear == 1985,2005,2021)
  




out_base <- paste0(species_f,spp,firstYear,"_",lastYear)




sp_data_file <- paste0("Data/",species_f,"_",firstYear,"_",lastYear,"_stan_data.RData")


load(sp_data_file)

## for both time-periods, there is a relatively strong spatial autocorrelation
## in both the habitat suitability and the mean abundance of the species
## Since, the spatial component of habitat suitability could reasonably be
## considered as a cause of the spatial dependency in abundance we estimated the
## residual component of the intercept term with a non-spatial (simple random effect)
## Setting this `spatial_intercept` to TRUE will fit the model with the spatial residual term
spatial_intercept <- FALSE
# trend habitat effects are not changed, but the intercept effect is
# removes the optional spatial components for intercepts 
stan_data[["fit_spatial"]] <- ifelse(spatial_intercept,1,0)

   mod.file = paste0("models/slope",spp,"route_NB.stan")


slope_model <- cmdstan_model(mod.file, stanc_options = list("Oexperimental"))

stanfit <- slope_model$sample(
  data=stan_data,
  refresh=400,
  iter_sampling=2000,
  iter_warmup=2000,
  parallel_chains = 4)

summ <- stanfit$summary()
print(paste(species, stanfit$time()[["total"]]))

saveRDS(stanfit,
        paste0(output_dir,"/",out_base,"_stanfit.rds"))

saveRDS(summ,
        paste0(output_dir,"/",out_base,"_summ_fit.rds"))

summ %>% arrange(-rhat)
summ %>% filter(variable %in% c("BETA","rho_BETA_hab"))
summ %>% filter(variable %in% c("ALPHA","rho_ALPHA_hab"))
summ %>% filter(grepl("T",variable))
summ %>% filter(grepl("CH",variable))




}


# graphing ----------------------------------------------------------------



firstYear <- 2006
lastYear <- ifelse(firstYear == 1985,2005,2021)

out_base <- paste0(species_f,spp,firstYear,"_",lastYear)

sp_data_file <- paste0("Data/",species_f,"_",firstYear,"_",lastYear,"_stan_data.RData")

load(sp_data_file)

summ <- readRDS(paste0(output_dir,"/",out_base,"_summ_fit.rds"))


mn0 <- new_data %>% 
  group_by(routeF) %>% 
  summarise(mn = mean(count),
            mx = max(count),
            ny = n(),
            fy = min(year),
            ly = max(year),
            sp = max(year)-min(year))

route_map_2006 <- route_map 

exp_t <- function(x){
  y <- (exp(x)-1)*100
}


# plot trends -------------------------------------------------------------


base_strata_map <- bbsBayes2::load_map("bbs_usgs")


strata_bounds <- st_union(route_map) #union to provide a simple border of the realised strata
bb = st_bbox(strata_bounds)
xlms = as.numeric(c(bb$xmin,bb$xmax))
ylms = as.numeric(c(bb$ymin,bb$ymax))

betas1 <- summ %>% 
  filter(grepl("beta[",variable,fixed = TRUE)) %>% 
  mutate(across(2:7,~exp_t(.x)),
         routeF = as.integer(str_extract(variable,"[[:digit:]]{1,}")),
         parameter = "Full with Habitat-Change") %>% 
  select(routeF,mean,sd,parameter) %>% 
  rename(trend = mean,
         trend_se = sd)

alpha1 <- summ %>% 
  filter(grepl("alpha[",variable,fixed = TRUE)) %>% 
  mutate(across(2:7,~exp(.x)),
         routeF = as.integer(str_extract(variable,"[[:digit:]]{1,}")),
         parameter = "Full with Habitat") %>% 
  select(routeF,median,sd) %>% 
  rename(abundance = median,
         abundance_se = sd)

alpha2 <- summ %>% 
  filter(grepl("alpha_resid[",variable,fixed = TRUE)) %>% 
  mutate(across(2:7,~exp(.x)),
         routeF = as.integer(str_extract(variable,"[[:digit:]]{1,}")),
         parameter = "Residual") %>% 
  select(routeF,median,sd) %>% 
  rename(abundance = median,
         abundance_se = sd)

betas1 <- betas1 %>% 
  inner_join(.,alpha1)

betas2 <- summ %>% 
  filter(grepl("beta_resid[",variable,fixed = TRUE)) %>% 
  mutate(across(2:7,~exp_t(.x)),
         routeF = as.integer(str_extract(variable,"[[:digit:]]{1,}")),
         parameter = "Residual") %>% 
  select(routeF,mean,sd,parameter) %>% 
  rename(trend = mean,
         trend_se = sd)
betas2 <- betas2 %>% 
  inner_join(.,alpha2,by = "routeF") %>% 
  inner_join(.,mn0,by = "routeF")


betas <- bind_rows(betas1,betas2)

plot_map <- route_map_2006 %>% 
  left_join(.,betas,
            by = "routeF",
            multiple = "all") 

breaks <- c(-7, -4, -2, -1, -0.5, 0.5, 1, 2, 4, 7)
lgnd_head <- "Mean Trend\n"
trend_title <- "Mean Trend"
labls = c(paste0("< ",breaks[1]),paste0(breaks[-c(length(breaks))],":", breaks[-c(1)]),paste0("> ",breaks[length(breaks)]))
labls = paste0(labls, " %/year")
plot_map$Tplot <- cut(plot_map$trend,breaks = c(-Inf, breaks, Inf),labels = labls)


map_palette <- c("#a50026", "#d73027", "#f46d43", "#fdae61", "#fee090", "#ffffbf",
                 "#e0f3f8", "#abd9e9", "#74add1", "#4575b4", "#313695")
names(map_palette) <- labls



map <- ggplot()+
  geom_sf(data = base_strata_map,
          fill = NA,
          colour = grey(0.75))+
  geom_sf(data = plot_map,
          aes(colour = Tplot,
              size = abundance))+
  scale_size_continuous(range = c(0.05,2),
                        name = "Mean Count")+
  scale_colour_manual(values = map_palette, aesthetics = c("colour"),
                      guide = guide_legend(reverse=TRUE),
                      name = paste0(lgnd_head))+
  coord_sf(xlim = xlms,ylim = ylms)+
  guides(size = "none")+
  scalebar(plot_map,
           dist = 250,
           dist_unit = "km",
           transform = FALSE,
           facet.var = "parameter",
           facet.lev = "Full with Habitat-Change",
           location = "bottomleft",
           st.size = 2.5,
           #box.fill = gray(0.7),
           #box.color = gray(0.7),
           st.color = gray(0.5))+
  xlab("")+
  ylab("")+
  # ggspatial::annotation_north_arrow(data = base_strata_map,
  #                                   aes(location = "tr"),
  #                                   style = north_arrow_minimal(
  #                                     line_width = 1,
  #                                     line_col = gray(0.7),
  #                                     fill = gray(0.7),
  #                                     text_col = gray(0.5),
  #                                     text_family = "",
  #                                     text_face = NULL,
  #                                     text_size = 10
  #                                   ))+
  north(plot_map, symbol = 3)+
  labs(title = paste(firstYear,"-",lastYear))+
  theme_bw()+
  facet_wrap(vars(parameter))


# map <- ggplot(plot_map)+
#   geom_sf()+
#   north(plot_map)
map



map_abund <- ggplot()+
  geom_sf(data = base_strata_map,
          fill = NA,
          colour = grey(0.75))+
  geom_sf(data = plot_map,
          aes(colour = abundance))+
  scale_colour_viridis_c(begin = 0.1, end = 0.9,
                         guide = guide_legend(reverse=TRUE),
                         name = paste0("Relative Abundance"))+
  coord_sf(xlim = xlms,ylim = ylms)+
  theme_bw()+
  xlab("")+
  ylab("")+
  north(plot_map, symbol = 3)+
  labs(title = paste(firstYear,"-",lastYear))+
  facet_wrap(vars(parameter))




map_se <- ggplot()+
  geom_sf(data = base_strata_map,
          fill = NA,
          colour = grey(0.75))+
  geom_sf(data = plot_map,
          aes(colour = trend_se,
              size = abundance_se))+
  scale_size_continuous(range = c(0.05,2),
                        name = "SE of Mean Count",
                        trans = "reverse")+
  scale_colour_viridis_c(aesthetics = c("colour"),
                         guide = guide_legend(reverse=TRUE),
                         name = paste0("SE of Trend"))+
  coord_sf(xlim = xlms,ylim = ylms)+
  theme_bw()+
  xlab("")+
  ylab("")+
  north(plot_map, symbol = 3)+
  guides(size = "none")+
  labs(title = paste(firstYear,"-",lastYear))+
  facet_wrap(vars(parameter))




#print(map2 / map_se2)

pdf(paste0("Figures/Figure_supplement_1_Trend_map_w_habitat_and_withing_",species_f,".pdf"),
    height = 10.5,
    width = 7.5)


print(map / map_se + plot_layout(guides = "collect"))


dev.off()

map_save <- map / map_abund + plot_layout(guides = "collect")
saveRDS(map_save,paste0("Figures/saved_map_",firstYear,".rds"))

pdf(paste0("Figures/Figure_4both.pdf"),
    height = 10,
    width = 7)


print(map / map_abund + plot_layout(guides = "collect"))


dev.off()

  
  
  


firstYear <- 1985
lastYear <- ifelse(firstYear == 1985,2005,2021)

out_base <- paste0(species_f,spp,firstYear,"_",lastYear)

sp_data_file <- paste0("Data/",species_f,"_",firstYear,"_",lastYear,"_stan_data.RData")

load(sp_data_file)

summ <- readRDS(paste0(output_dir,"/",out_base,"_summ_fit.rds"))



mn0 <- new_data %>% 
  group_by(routeF) %>% 
  summarise(mn = mean(count),
            mx = max(count),
            ny = n(),
            fy = min(year),
            ly = max(year),
            sp = max(year)-min(year))

route_map_2006 <- route_map 

exp_t <- function(x){
  y <- (exp(x)-1)*100
}


# plot trends -------------------------------------------------------------


base_strata_map <- bbsBayes2::load_map("bbs_usgs")


strata_bounds <- st_union(route_map) #union to provide a simple border of the realised strata
bb = st_bbox(strata_bounds)
xlms = as.numeric(c(bb$xmin,bb$xmax))
ylms = as.numeric(c(bb$ymin,bb$ymax))

betas1 <- summ %>% 
  filter(grepl("beta[",variable,fixed = TRUE)) %>% 
  mutate(across(2:7,~exp_t(.x)),
         routeF = as.integer(str_extract(variable,"[[:digit:]]{1,}")),
         parameter = "Full with Habitat-Change") %>% 
  select(routeF,mean,sd,parameter) %>% 
  rename(trend = mean,
         trend_se = sd)


alpha1 <- summ %>% 
  filter(grepl("alpha[",variable,fixed = TRUE)) %>% 
  mutate(across(2:7,~exp(.x)),
         routeF = as.integer(str_extract(variable,"[[:digit:]]{1,}")),
         parameter = "Full with Habitat") %>% 
  select(routeF,median,sd) %>% 
  rename(abundance = median,
         abundance_se = sd)

alpha2 <- summ %>% 
  filter(grepl("alpha_resid[",variable,fixed = TRUE)) %>% 
  mutate(across(2:7,~exp(.x)),
         routeF = as.integer(str_extract(variable,"[[:digit:]]{1,}")),
         parameter = "Residual") %>% 
  select(routeF,median,sd) %>% 
  rename(abundance = median,
         abundance_se = sd)

betas1 <- betas1 %>% 
  inner_join(.,alpha1)

betas2 <- summ %>% 
  filter(grepl("beta_resid[",variable,fixed = TRUE)) %>% 
  mutate(across(2:7,~exp_t(.x)),
         routeF = as.integer(str_extract(variable,"[[:digit:]]{1,}")),
         parameter = "Residual") %>% 
  select(routeF,mean,sd,parameter) %>% 
  rename(trend = mean,
         trend_se = sd)
betas2 <- betas2 %>% 
  inner_join(.,alpha2,by = "routeF") %>% 
  inner_join(.,mn0,by = "routeF")


betas <- bind_rows(betas1,betas2)

plot_map <- route_map_2006 %>% 
  left_join(.,betas,
            by = "routeF",
            multiple = "all") 

breaks <- c(-7, -4, -2, -1, -0.5, 0.5, 1, 2, 4, 7)
lgnd_head <- "Mean Trend\n"
trend_title <- "Mean Trend"
labls = c(paste0("< ",breaks[1]),paste0(breaks[-c(length(breaks))],":", breaks[-c(1)]),paste0("> ",breaks[length(breaks)]))
labls = paste0(labls, " %/year")
plot_map$Tplot <- cut(plot_map$trend,breaks = c(-Inf, breaks, Inf),labels = labls)


map_palette <- c("#a50026", "#d73027", "#f46d43", "#fdae61", "#fee090", "#ffffbf",
                 "#e0f3f8", "#abd9e9", "#74add1", "#4575b4", "#313695")
names(map_palette) <- labls



map <- ggplot()+
  geom_sf(data = base_strata_map,
          fill = NA,
          colour = grey(0.75))+
  geom_sf(data = plot_map,
          aes(colour = Tplot,
              size = abundance))+
  scale_size_continuous(range = c(0.05,2),
                        name = "Mean Count")+
  scale_colour_manual(values = map_palette, aesthetics = c("colour"),
                      guide = guide_legend(reverse=TRUE),
                      name = paste0(lgnd_head))+
  coord_sf(xlim = xlms,ylim = ylms)+
  theme_bw()+
  xlab("")+
  ylab("")+
  guides(size = "none")+
  scalebar(plot_map,
           dist = 250,
           dist_unit = "km",
           transform = FALSE,
           facet.var = "parameter",
           facet.lev = "Full with Habitat-Change",
           location = "bottomleft",
           st.size = 2.5,
           #box.fill = gray(0.7),
           #box.color = gray(0.7),
           st.color = gray(0.5))+
  north(plot_map, symbol = 3)+
  labs(title = paste(firstYear,"-",lastYear))+
  facet_wrap(vars(parameter))



map_abund <- ggplot()+
  geom_sf(data = base_strata_map,
          fill = NA,
          colour = grey(0.75))+
  geom_sf(data = plot_map,
          aes(colour = abundance))+
  scale_colour_viridis_c(begin = 0.1, end = 0.9,
                         guide = guide_legend(reverse=TRUE),
                         name = paste0("Relative Abundance"))+
  coord_sf(xlim = xlms,ylim = ylms)+
  xlab("")+
  ylab("")+
  theme_bw()+
  north(plot_map, symbol = 3)+
  labs(title = paste(firstYear,"-",lastYear))+
  facet_wrap(vars(parameter))


#map

# pdf(paste0("Figures/Four_trends_model_comparison_",species_f,".pdf"),
#     height = 8,
#     width = 8)
# print(map)
# dev.off()

map_se <- ggplot()+
  geom_sf(data = base_strata_map,
          fill = NA,
          colour = grey(0.75))+
  geom_sf(data = plot_map,
          aes(colour = trend_se,
              size = abundance_se))+
  scale_size_continuous(range = c(0.05,2),
                        name = "SE of Mean Count",
                        trans = "reverse")+
  scale_colour_viridis_c(aesthetics = c("colour"),
                         guide = guide_legend(reverse=TRUE),
                         name = paste0("SE of Trend"))+
  coord_sf(xlim = xlms,ylim = ylms)+
  xlab("")+
  ylab("")+
  theme_bw()+
  north(plot_map, symbol = 3)+
  guides(size = "none")+
  labs(title = paste(firstYear,"-",lastYear))+
  facet_wrap(vars(parameter))




#print(map2 / map_se2)

pdf(paste0("Figures/Figure_supplement_1_1985_Trend_map_w_habitat_and_without_",species_f,".pdf"),
    height = 10.5,
    width = 7.5)


print(map / map_se + plot_layout(guides = "collect"))


dev.off()

map_save <- map / map_abund + plot_layout(guides = "collect")
saveRDS(map_save,paste0("Figures/saved_map_",firstYear,".rds"))
pdf(paste0("Figures/Figure_4both_1985.pdf"),
    height = 10,
    width = 7)


print(map / map_abund + plot_layout(guides = "collect"))


dev.off()


# summarise the parameters ------------------------------------------------

hypers_out <- NULL
route_params_out <- NULL


for(firstYear in c(1985,2006)){
lastYear <- ifelse(firstYear == 1985,2005,2021)

out_base <- paste0(species_f,spp,firstYear,"_",lastYear)

sp_data_file <- paste0("Data/",species_f,"_",firstYear,"_",lastYear,"_stan_data.RData")

load(sp_data_file)

summ <- readRDS(paste0(output_dir,"/",out_base,"_summ_fit.rds"))


betahabs <- summ %>% 
  filter(grepl("beta_hab[",variable,fixed = TRUE))  %>% 
  mutate(across(2:7,~exp_t(.x)),
         firstyear = firstYear,
         parameter = "Rho_beta_r")
alphahabs <- summ %>% 
  filter(grepl("alpha_hab[",variable,fixed = TRUE))  %>% 
  mutate(across(2:7,~exp(.x)),
         firstyear = firstYear,
         parameter = "Rho_alpha_r")
route_params_out <- bind_rows(route_params_out,betahabs)
route_params_out <- bind_rows(route_params_out,alphahabs)


Bhabs <- summ %>% 
  filter(grepl("rho_BETA_hab",variable,fixed = TRUE)) %>% 
  mutate(firstyear = firstYear,
         parameter = "Rho_beta")
Ahabs <- summ %>% 
  filter(grepl("rho_ALPHA_hab",variable,fixed = TRUE)) %>% 
  mutate(firstyear = firstYear,
         parameter = "Rho_alpha")
CH <- summ %>% 
  filter(variable == "CH") %>% 
  mutate(firstyear = firstYear)
TT <- summ %>% 
  filter(variable %in% c("T","T_no_habitat")) %>% 
  mutate(firstyear = firstYear)
hypers_out <- bind_rows(hypers_out,Bhabs)
hypers_out <- bind_rows(hypers_out,Ahabs)
hypers_out <- bind_rows(hypers_out,CH)
hypers_out <- bind_rows(hypers_out,TT)

}

saveRDS(hypers_out,"saved_hyperparameters.rds")
saveRDS(route_params_out,"saved_route_parameters.rds")



  