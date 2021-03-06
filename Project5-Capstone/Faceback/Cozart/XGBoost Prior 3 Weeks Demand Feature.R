setwd("C:/Users/Hayes/Desktop/BDS 005/Projects/Project 5 test")

library(hash)
library(data.table)
library(Metrics)
library(foreach)
library(dplyr)
library(xgboost)
library(doParallel)
registerDoParallel(2)
library(slackr)
library(Matrix)

slackr_setup(channel = "@hcozart", username = "i_bimbobot", icon_emoji = "",
             incoming_webhook_url = "datasqawd.slack.com", api_token = "xoxb-51493476675-ZkuheKfwDSdeEtTok0NRPcG6",
             echo = FALSE)

train <- fread("train_with_mde_feature.csv")

str(train)

#impute NA's of lags as 0

train[is.na(train)] <- 0

#sum the prior three weeks lag

train[, PriorDemand := Lag1 + Lag2 + Lag3]

#remove pred

train <- select(train,-11)


#xgboost model

test <- train[Semana == 9, ]
train <- train[Semana < 9, ]


train.y <- train$Demanda_uni_equil

test.y <- test$Demanda_uni_equil
test$Demanda_uni_equil <- NULL

memory.size()

gc()

memory.limit(size = 20000)

train.model <- sparse.model.matrix(Demanda_uni_equil ~ ., data = train)

gc()

dtrain <- xgb.DMatrix(data = train.model, label = train.y)
watchlist <- list(train=dtrain)
rm(train.model,train)

gc()

depths = c(18, 19, 20, 21, 22)
results = as.numeric(1:length(depths))

for (depth_cv in 1:length(depths)) {
  set.seed(1234)
  param <- list(  objective           = "reg:linear",
                  booster             = "gbtree",
                  eval_metric         = "rmse",
                  eta                 = 0.2,
                  max_depth           = depths[depth_cv]
  )
  
  clf <- xgb.train(   params              = param, 
                      data                = dtrain, 
                      nrounds             = 10,
                      verbose             = 1,
                      watchlist           = watchlist,
                      maximize            = FALSE
  )
  
  test$Demanda_uni_equil <- -1
  test.model <- sparse.model.matrix(Demanda_uni_equil ~ ., data = test)
  
  gc()
  
  preds <- predict(clf, test.model)
  test.y <- as.numeric(test.y)
  
  gc()
  
  preds[preds < 0] = 0.1
  result = rmsle(test.y, preds)
  
  results[depth_cv] = result
  message = paste0("Hey Hayes ;), for depth ", depths[depth_cv], ", your rmsle was: ", result)
  slackr(message)
  to_csv = data.frame(nrounds = depths, results = results)
  write.csv(to_csv, "results_with_lag_feature_priordemand.csv", row.names = F)
}
