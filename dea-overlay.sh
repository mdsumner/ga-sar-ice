#!/bin/bash
# dea-overlay.sh: add the GA Digital Earth Antarctica SAR notebooks to a gdal-r-ci Python venv.
# Run inside ghcr.io/hypertidy/gdal-r-python(-extras):latest, or on a Nectar server built by mdsumner/nectar's recipes
# with --python-full (its /opt/gdal-py is lifted from gdal-r-python). Idempotent. https://github.com/mdsumner/ga-sar-ice
#
# Usage:  dea-overlay.sh [--sam] [DIR]
#   DIR    where to clone the repos (default ~/dea)
#   --sam  also install the fast-ice Segment Anything + SVM stack (CPU torch, ~1 GB) and vit_b weights
#
# Everything else the notebooks use (rasterio, geopandas, pyogrio, odc-geo, rioxarray, pystac-client,
# stac-geoparquet, pyarrow, xarray, dask, jupyterlab, marimo) is already in the image, source-built
# against the image's GDAL. This only adds what is missing, and installs the GA packages with --no-deps
# so their tight pins (pystac-client <0.9, stac-geoparquet <0.8 vs >=0.8, ...) don't downgrade the stack.
set -euo pipefail
PY=${PY:-/opt/gdal-py/bin/python}
SAM=
while [ $# -gt 0 ]; do case $1 in --sam) SAM=1; shift;; *) break;; esac; done
DIR=${1:-$HOME/dea}
UV="uv pip install --python $PY"

echo "== python packages not in the image"
$UV "odc-stac>=0.5.2,<0.6" folium ipywidgets scikit-image scikit-learn loguru asf_search

echo "== GA repos into $DIR"
mkdir -p "$DIR"; cd "$DIR"
clone() { [ -d "$2" ] && git -C "$2" pull -q --ff-only || git clone -q "https://github.com/$1" "$2"; }
clone abradley60/fast-ice fast-ice
clone jlo031/normalized_covariance fast-ice/normalized_covariance   # fast-ice's pyproject expects it here
clone eloise-b/de-sar-sample-data de-sar-sample-data
$UV --no-deps -e fast-ice/normalized_covariance -e fast-ice -e de-sar-sample-data

if [ -n "$SAM" ]; then
  echo "== SAM + SVM stack (CPU torch)"
  $UV --index-url https://download.pytorch.org/whl/cpu torch torchvision
  $UV opencv-python-headless pycocotools supervision onnx onnxruntime onnxscript joblib \
      "segment-anything @ git+https://github.com/facebookresearch/segment-anything.git"
  W=fast-ice/fast_ice/sam/weights; mkdir -p "$W"
  [ -f "$W/sam_vit_b_01ec64.pth" ] || curl -fsSL -o "$W/sam_vit_b_01ec64.pth" \
    https://dl.fbaipublicfiles.com/segment_anything/sam_vit_b_01ec64.pth
  echo "   vit_b weights in $W; use SAMSegmenter(model_type='vit_b') on CPU (vit_h is 2.4 GB)"
fi

echo "== checks"
$PY - <<'PY'
import pandas, stac_geoparquet, odc.stac, pystac_client, rasterio
from osgeo import gdal
from normalized_covariance import normcovar
from de_sar_demo.speckle_filters import lee_filter_xr
print("GDAL", gdal.__version__, "| rasterio GDAL", rasterio.__gdal_version__)
print("pandas", pandas.__version__, "| stac-geoparquet", stac_geoparquet.__version__, "| odc-stac", odc.stac.__version__)
if int(pandas.__version__.split(".")[0]) >= 3:
    print("NOTE pandas 3: cast datetimetz columns to datetime64[ns, UTC] before stac_geoparquet.to_item_collection()")
PY
gdal --version 2>/dev/null || gdalinfo --version
ogrinfo --formats | grep -iq parquet && echo "GDAL Parquet driver: yes (EW STAC-GeoParquet readable from R via gdalraster/terra/vapour)"
echo "done: notebooks in $DIR/fast-ice/notebooks and $DIR/de-sar-sample-data/demo_notebooks/tutorial_c1"
