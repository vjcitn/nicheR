library(SingleCellExperiment)
library(Matrix)
library(RcppCNPy)   # for loading .npy mean vectors

# ------------------------------------------------------------------
# Step 1: Load technology-specific mean vector
# (xenium_mean_script.npy, cosmx_mean_script.npy, iss_mean_script.npy)
# ------------------------------------------------------------------
load_tech_mean <- function(npy_path) {
  RcppCNPy::npyLoad(npy_path)  # returns a numeric vector
} 

xen_mean = load_tech_mean(system.file("model_means", "xenium_mean_float32.npy", package="nicheR"))

