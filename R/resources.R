.osn_bucket_to_cache <- function(
    entity, folder = "BiocScviR",
    prefix = "https://mghp.osn.xsede.org/bir190004-bucket01/",
    ca = BiocFileCache::BiocFileCache()) {
  pa <- BiocFileCache::bfcquery(ca, entity)
  if (nrow(pa) > 1) {
    stop(sprintf(
      "%s has multiple instances in cache, please inspect.",
      entity
    ))
  } else if (nrow(pa) == 1) {
    return(pa$rpath)
  }
  target <- paste0(prefix, folder, "/", entity)
  tf <- tempfile(entity) # for metadata
  download.file(target, tf)
  BiocFileCache::bfcrpath(ca, tf, action = "copy")
}

#' retrieve (and cache if necessary) weights or example data for
#' nicheformer
#' @param entity "lungx.zip" (27MB) or "nicheformer_weights.safetensors" (197MB)
#' @examples
#' zpa = getNicheResource("lungx.zip")
#' td = tempdir()
#' unzip(zpa, exdir=td)
#' scedir = dir(td, patt="lungXen", full=TRUE)
#' requireNamespace("alabaster.sce")
#' sce = alabaster.base::readObject(scedir)
#' sce
#' @export
getNicheResource = function(entity) {
  stopifnot( entity %in% c("lungx.zip", "nicheformer_weights.safetensors"))
  .osn_bucket_to_cache(entity, folder="BiocNicheWeights")
}

