# Set the working directory
setwd(dirname(rstudioapi::getActiveDocumentContext()$path))

# Load the required libraries
if (!require("xts")) install.packages("xts", dependencies = TRUE); library("xts")
if (!require("dplyr")) install.packages("dplyr", dependencies = TRUE); library("dplyr")
if (!require("tidyverse")) install.packages("tidyverse", dependencies = TRUE); library("tidyverse")
if (!require("frenchdata")) install.packages("frenchdata", dependencies = TRUE); library("frenchdata")
if (!require("knitr")) install.packages("knitr", dependencies = TRUE); library("knitr")
if (!require("kableExtra")) install.packages("kableExtra", dependencies = TRUE); library("kableExtra")

# Obtain the daily Fama French 3 factors
ff3_data_daily <- download_french_data("Fama/French 3 Factors [Daily]")
ff3_data_daily <- ff3_data_daily$subsets$data[[1]] |>
  transmute(
    date = as.Date(paste0(substr(date,1,4),"-",substr(date,5,6),"-",substr(date,7,8))),
    Mkt.RF = as.numeric(`Mkt-RF`),
    SMB = as.numeric(SMB),
    HML = as.numeric(HML)
  ) |> 
  as.data.frame()

# Obtain the monthly Fama French 3 factors
ff3_data_monthly <- download_french_data("Fama/French 3 Factors")
ff3_data_monthly <- ff3_data_monthly$subsets$data[[1]] |>
  transmute(
    date = as.Date(paste0(substr(date,1,4),"-",substr(date,5,6),"-","01")),
    Mkt.RF = as.numeric(`Mkt-RF`),
    SMB = as.numeric(SMB),
    HML = as.numeric(HML)
  ) |> 
  as.data.frame()


## Replication of findings from the paper

# Set the time period
start_date <- as.Date("1926-07-01")
end_date <- as.Date("2015-12-31")

# Convert the daily data to an xts object and filter for the correct time period
factors_daily_ret <- xts(ff3_data_daily[,-1], order.by = ff3_data_daily[,1])
factors_daily_ret <- factors_daily_ret[as.Date(start_date:end_date)]

# Convert the monthly data to an xts object and filter for the correct time period
factors_monthly_ret <- xts(ff3_data_monthly[-1,-1], order.by = ff3_data_monthly[-1,1]) 
factors_monthly_ret <- factors_monthly_ret[as.Date(start_date:end_date)]

# Calculate the realized volatility as a proxy for conditional variance
factors_monthly_con_var <- apply.monthly(factors_daily_ret$Mkt.RF, function(i) {
  D <- nrow(i)
  con_var <- sum((i - sum(i)/D)^2)
  return(con_var)
}) 

# We need to exclude the last month in the time series for conditional variance since we need to shift the time series by one month ahead in order to match the conditional variance with the following month
factors_monthly_con_var <- factors_monthly_con_var[-nrow(factors_monthly_con_var),] 
# Round the dates to the beginning of the month and shift the time series by one month ahead 
index(factors_monthly_con_var) <- floor_date(index(factors_monthly_con_var), "month") + months(1)

# Obtain the standard deviation for a given month and exclude the first month since we do not have the conditional variance for the first month in the time series
factors_monthly_sd <- apply.monthly(factors_daily_ret$Mkt.RF, sd)
index(factors_monthly_sd) <- floor_date(index(factors_monthly_sd), "month")
factors_monthly_sd <- factors_monthly_sd[-1,]

# Obtain the variance for a given month and exclude the first month since we do not have the conditional variance for the first month in the time series
factors_monthly_var <- apply.monthly(factors_daily_ret$Mkt.RF, var)
index(factors_monthly_var) <- floor_date(index(factors_monthly_var), "month")
factors_monthly_var <- factors_monthly_var[-1,]

# Calculate the average monthly returns per unit of variance
factor_monthly_retpervar <- factors_monthly_ret$Mkt.RF / factors_monthly_var$Mkt.RF

# Sort the returns, standard deviation, and returns per unit of variance into 5 buckets with 20% of observations each
factors_monthly_ret$sorts <- ntile(factors_monthly_con_var$Mkt.RF, 5)
factors_monthly_sd$sorts <- ntile(factors_monthly_con_var$Mkt.RF, 5)
factor_monthly_retpervar$sorts <- ntile(factors_monthly_con_var$Mkt.RF, 5)

# Convert the returns to yearly
factors_monthly_ret <- factors_monthly_ret * 12

# Convert the standard deviation to monthly
factors_monthly_sd <- factors_monthly_sd * 22

# Calculate the average values per sorting variable
factors_monthly_ret_sorts <- tapply(factors_monthly_ret$Mkt.RF, factors_monthly_ret$sorts, mean)
factors_monthly_sd_sorts <- tapply(factors_monthly_sd$Mkt.RF, factors_monthly_sd$sorts, mean)
factor_monthly_retpervar_sorts <- tapply(factor_monthly_retpervar$Mkt.RF, factor_monthly_retpervar$sorts, mean) 

# Rename the sorting variable
names(factors_monthly_ret_sorts) <- c("Low Vol","2","3","4","High Vol")
names(factors_monthly_sd_sorts) <- c("Low Vol","2","3","4","High Vol")
names(factor_monthly_retpervar_sorts) <- c("Low Vol","2","3","4","High Vol")

# Plot the results
png(file="out/sorts_1.png", width=8, height=4, units="in", res=600)
par(mfrow=c(2,2), mar=c(3,3,2,0.5), cex=0.7)
barplot(factors_monthly_ret_sorts, main="Average Return", col="darkblue", border = "black", ylim = c(0,12))
barplot(factors_monthly_sd_sorts, main="Standard Deviation", col="darkblue", ylim = c(0,40))
barplot(factor_monthly_retpervar_sorts, main="E[R]/Var(R)", col="darkblue", ylim = c(0,8))
dev.off()

# Calculate c given that the standard deviation of the buy-and-hold portfolio should be the same as the standard deviation of the managed portfolio
c <- sd(factors_monthly_ret$Mkt.RF) / sd(factors_monthly_ret$Mkt.RF / factors_monthly_con_var$Mkt.RF)

# Calculate the returns of the managed portfolio with the given formula
managed_portfolio <- c/factors_monthly_con_var$Mkt.RF * factors_monthly_ret$Mkt.RF

# Run linear regression for the volatility-managed portfolio
vol_portfolio <- lm(managed_portfolio$Mkt.RF ~ factors_monthly_ret$Mkt.RF)

# Run linear regression for the control Fama-French 3 factors portfolio
vol_portfolio_control <- lm(managed_portfolio$Mkt.RF ~ factors_monthly_ret$Mkt.RF + 
                              factors_monthly_ret$SMB + factors_monthly_ret$HML)

# Create a table for panel a with the regression results and format the column names
table1.a <- cbind(vol_portfolio$coefficients[2], summary(vol_portfolio)$coefficients[2,2], 
                  vol_portfolio$coefficients[1], summary(vol_portfolio)$coefficients[1,2], 
                  nobs(vol_portfolio), summary(vol_portfolio)$r.squared,  
                  sqrt(mean((vol_portfolio$fitted.values - managed_portfolio$Mkt.RF)^2)))
rownames(table1.a) <- "Mkt.sigma"
colnames(table1.a) <- c("MktRF","Standard Error (MktRF)","Alpha","Standard Error (Alpha)","N","R.squared","RMSE")

# Display the table for panel a
print(table1.a)

# Create a table for panel a with the regression results and format the column names
table1.a.html <- table1.a
rownames(table1.a.html) <- "Mkt$^\\sigma$"
colnames(table1.a.html) <- c("MktRF"," ","Alpha ($\\alpha$)"," ","$N$","$R^2$","RMSE")

# Round the numbers in the table
table1.a.html <- round(table1.a.html, 2)
table1.a.html[,5] <- round(table1.a.html[,5], 0)
table1.a.html[,c(2,4)] <- paste("(", table1.a.html[,c(2,4)], ")", sep = "")

# Display the table for panel a
table1.a.html <- kbl(t(table1.a.html), booktabs = TRUE, escape = FALSE, align = "c",
    caption="Volatility-Managed Factor Alphas") %>%
  kable_styling(position = "left", latex_options = c("hold_position"), full_width = T, font_size = 10) %>%
  column_spec(1, width = "6cm")  %>%
  add_header_above(c(" "=1,"(1)"=1), align="c", line=F, line_sep = 5)  %>%
  add_header_above(c("Panel A: Univariate Regressions"=2), align="c", bold=T, line=F, line_sep = 5) 
save_kable(table1.a.html, file = "out/table1.a.org.html")

# Create a table for panel b with the regression results and format the column names
table1.b <- cbind(vol_portfolio_control$coefficients[1], summary(vol_portfolio_control)$coefficients[1,2])
rownames(table1.b) <- ""
colnames(table1.b) <- c("Alpha","Standard Error (Alpha)")

# Display the table for panel b
print(table1.b)

# Create a table for panel b with the regression results and format the column names
table1.b.html <- table1.b
table1.b.html <- cbind(vol_portfolio_control$coefficients[1], summary(vol_portfolio_control)$coefficients[1,2])
rownames(table1.b.html) <- ""
colnames(table1.b.html) <- c("Alpha ($\\alpha$)"," ")

# Round the numbers in the table
table1.b.html <- round(table1.b.html, 2)
table1.b.html[,2] <- paste("(", table1.b.html[,2], ")", sep = "")

# Display the table for panel b
table1.b.html <- kbl(t(table1.b.html), booktabs = TRUE, escape = FALSE, align = "c") %>%
  kable_styling(position = "left", latex_options = c("hold_position"), full_width = T, font_size = 10) %>%
  column_spec(1, width = "6cm")  %>%
  add_header_above(c("Panel B: Alphas Controlling for Fama-French Three Factors"=2), align="c", bold=T, line=F, line_sep = 5) 
save_kable(table1.b.html, file = "out/table1.b.org.html")


## New analysis (1)

# Set the time period
start_date <- as.Date("1926-07-01")
end_date <- as.Date("2023-07-31")

# Convert the daily data to an xts object and filter for the correct time period
factors_daily_ret <- xts(ff3_data_daily[,-1], order.by = ff3_data_daily[,1])
factors_daily_ret <- factors_daily_ret[as.Date(start_date:end_date)]

# Convert the monthly data to an xts object and filter for the correct time period
factors_monthly_ret <- xts(ff3_data_monthly[,-1], order.by = ff3_data_monthly[,1])
factors_monthly_ret <- factors_monthly_ret[as.Date(start_date:end_date)]

# Set the number of days that should be used to calculate the conditional variance
D <- 91

# Calculate the realized volatility as a proxy for conditional variance
factors_monthly_con_var <- apply.monthly(factors_daily_ret$Mkt.RF[-c(1:D)], function(i) {
  min_index <- which(index(factors_daily_ret$Mkt.RF)==min(index(i)))
  time_period <- seq.Date(index(factors_daily_ret$Mkt.RF[min_index-D]), min(index(i)) - days(1), by="days")
  con_var <- D/22 * sum((factors_daily_ret$Mkt.RF[time_period] - sum(factors_daily_ret$Mkt.RF[time_period]) / D)^2)
  return(con_var)
})

# Round the dates to the beginning of the month
index(factors_monthly_con_var) <- floor_date(index(factors_monthly_con_var), "month")

# Filter the monthly returns for the same time period as included in the conditional variance data frame since conditional variance cannot be calculated for the first D number of days
factors_monthly_ret <- factors_monthly_ret[index(factors_monthly_con_var)]

# Obtain the standard deviation for a given month and exclude the first D number of days since we do not have the conditional variance for the D number of days in the time series
factors_monthly_sd <- apply.monthly(factors_daily_ret$Mkt.RF[-c(1:D)], sd) 
index(factors_monthly_sd) <- floor_date(index(factors_monthly_sd), "month")

# Obtain the variance for a given month and exclude the first D number of days since we do not have the conditional variance for the first D number of days in the time series
factors_monthly_var <- apply.monthly(factors_daily_ret$Mkt.RF[-c(1:D)], var)
index(factors_monthly_var) <- floor_date(index(factors_monthly_var), "month")

# Calculate the average monthly returns per unit of variance
factor_monthly_retpervar <- factors_monthly_ret$Mkt.RF / factors_monthly_var$Mkt.RF

# Sort the returns, standard deviation, and returns per unit of variance to 5 buckets with 20% of observations each
factors_monthly_ret$sorts <- ntile(factors_monthly_con_var$Mkt.RF, 5)
factors_monthly_sd$sorts <- ntile(factors_monthly_con_var$Mkt.RF, 5)
factor_monthly_retpervar$sorts <- ntile(factors_monthly_con_var$Mkt.RF, 5)

# Convert the returns to yearly
factors_monthly_ret <- factors_monthly_ret * 12

# Convert the standard deviation to monthly
factors_monthly_sd <- factors_monthly_sd * 22

# Calculate the average values per sorting variable
factors_monthly_ret_sorts <- tapply(factors_monthly_ret$Mkt.RF, factors_monthly_ret$sorts, mean) 
factors_monthly_sd_sorts <- tapply(factors_monthly_sd$Mkt.RF, factors_monthly_sd$sorts, mean)
factor_monthly_retpervar_sorts <- tapply(factor_monthly_retpervar$Mkt.RF, factor_monthly_retpervar$sorts, mean) 

# Rename the sorting variable
names(factors_monthly_ret_sorts) <- c("Low Vol","2","3","4","High Vol")
names(factors_monthly_sd_sorts) <- c("Low Vol","2","3","4","High Vol")
names(factor_monthly_retpervar_sorts) <- c("Low Vol","2","3","4","High Vol")

# Plot the results
png(file="out/sorts_2.png", width=8, height=4, units="in", res=600)
par(mfrow=c(2,2), mar=c(3,3,2,0.5), cex=0.7)
barplot(factors_monthly_ret_sorts, main="Average Return", col="darkblue", border = "black", ylim = c(0,12))
barplot(factors_monthly_sd_sorts, main="Standard Deviation", col="darkblue", ylim = c(0,40))
barplot(factor_monthly_retpervar_sorts, main="E[R]/Var(R)", col="darkblue", ylim = c(0,8))
dev.off()

# Calculate the c given that we know that the standard deviation of the buy-and-hold portfolio should be the same as the standard deviation of the managed portfolio
c <- sd(factors_monthly_ret$Mkt.RF) / sd(factors_monthly_ret$Mkt.RF / factors_monthly_con_var$Mkt.RF)

# Calculate the returns of the managed portfolio with the given formula
managed_portfolio <- c/factors_monthly_con_var$Mkt.RF * factors_monthly_ret$Mkt.RF

# Run linear regression for the volatility managed portfolio
vol_portfolio <- lm(managed_portfolio$Mkt.RF ~ factors_monthly_ret$Mkt.RF)

# Run linear regression for the control Fama French 3 factors portfolio
vol_portfolio_control <- lm(managed_portfolio$Mkt.RF ~ factors_monthly_ret$Mkt.RF + 
                              factors_monthly_ret$SMB + factors_monthly_ret$HML)

# Create a table for panel a with the regression results and format the column names
table1.a <- cbind(vol_portfolio$coefficients[2], summary(vol_portfolio)$coefficients[2,2], 
                  vol_portfolio$coefficients[1], summary(vol_portfolio)$coefficients[1,2], 
                  nobs(vol_portfolio), summary(vol_portfolio)$r.squared,  
                  sqrt(mean((vol_portfolio$fitted.values - managed_portfolio$Mkt.RF)^2)))
rownames(table1.a) <- "Mkt.sigma"
colnames(table1.a) <- c("MktRF","Standard Error (MktRF)","Alpha","Standard Error (Alpha)","N","R.squared","RMSE")

# Display the table for panel a
print(table1.a)

# Create a table for panel a with the regression results and format the column names
table1.a.html <- table1.a
rownames(table1.a.html) <- "Mkt$^\\sigma$"
colnames(table1.a.html) <- c("MktRF"," ","Alpha ($\\alpha$)"," ","$N$","$R^2$","RMSE")

# Round the numbers in the table
table1.a.html <- round(table1.a.html, 2)
table1.a.html[,5] <- round(table1.a.html[,5], 0)
table1.a.html[,c(2,4)] <- paste("(", table1.a.html[,c(2,4)], ")", sep = "")

# Display the table for panel a
table1.a.html <- kbl(t(table1.a.html), booktabs = TRUE, escape = FALSE, align = "c",
                     caption="Volatility-Managed Factor Alphas") %>%
  kable_styling(position = "left", latex_options = c("hold_position"), full_width = T, font_size = 10) %>%
  column_spec(1, width = "6cm")  %>%
  add_header_above(c(" "=1,"(1)"=1), align="c", line=F, line_sep = 5)  %>%
  add_header_above(c("Panel A: Univariate Regressions"=2), align="c", bold=T, line=F, line_sep = 5) 
save_kable(table1.a.html, file = "out/table1.a.new.html")

# Create a table for panel b with the regression results and format the column names
table1.b <- cbind(vol_portfolio_control$coefficients[1], summary(vol_portfolio_control)$coefficients[1,2])
rownames(table1.b) <- ""
colnames(table1.b) <- c("Alpha","Standard Error (Alpha)")

# Display the table for panel b
print(table1.b)

# Create a table for panel b with the regression results and format the column names
table1.b.html <- table1.b
table1.b.html <- cbind(vol_portfolio_control$coefficients[1], summary(vol_portfolio_control)$coefficients[1,2])
rownames(table1.b.html) <- ""
colnames(table1.b.html) <- c("Alpha ($\\alpha$)"," ")

# Round the numbers in the table
table1.b.html <- round(table1.b.html, 2)
table1.b.html[,2] <- paste("(", table1.b.html[,2], ")", sep = "")

# Display the table for panel b
table1.b.html <- kbl(t(table1.b.html), booktabs = TRUE, escape = FALSE, align = "c") %>%
  kable_styling(position = "left", latex_options = c("hold_position"), full_width = T, font_size = 10) %>%
  column_spec(1, width = "6cm")  %>%
  add_header_above(c("Panel B: Alphas Controlling for Fama-French Three Factors"=2), align="c", bold=T, line=F, line_sep = 5) 
save_kable(table1.b.html, file = "out/table1.b.new.html")
