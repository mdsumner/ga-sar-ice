# ga-sar-ice

Notes and a setup script for working with Geoscience Australia's experimental
Sentinel-1 radar backscatter for Antarctica (Digital Earth Antarctica), and the
GA notebooks that detect landfast ice. The data is in public object storage, so
you don't need GA's own sandbox: any machine with a GDAL-linked Python stack works.

> **Status:** exploratory. Tested in the `gdal-r-python` container (2026-11-09);
> not yet run on a Nectar VM or in Codespaces.

## Set up

`dea-overlay.sh` adds the notebooks and their extra packages to the Python geo
stack in [gdal-r-ci](https://github.com/hypertidy/gdal-r-ci)'s `gdal-r-python`
image (rasterio, geopandas, pyogrio, odc-geo, rioxarray, pystac-client,
stac-geoparquet, xarray, dask, JupyterLab, all built against the same GDAL as R's
sf and terra). It installs `odc-stac`, scikit-image/learn, folium, asf_search and
a few more, then clones and installs:

- [fast-ice](https://github.com/abradley60/fast-ice), with
  [normalized_covariance](https://github.com/jlo031/normalized_covariance)
- [de-sar-sample-data](https://github.com/eloise-b/de-sar-sample-data)

`--sam` adds the Segment Anything model that fast-ice uses to cut images into
regions: CPU PyTorch (about 1 GB) and the smallest (`vit_b`) weights.

**Docker**, anywhere:

```bash
docker run --rm -it -p 8888:8888 -v "$PWD":/workspace ghcr.io/hypertidy/gdal-r-python:latest bash
# inside, in /workspace (a clone of this repo):
bash dea-overlay.sh dea
cd dea && jupyter lab --ip 0.0.0.0 --allow-root --no-browser
```

**Codespaces**: open this repo in a codespace; `.devcontainer/` runs the overlay
into `dea/`. The image is about 11 GB, so the first start is slow.

**Nectar**: build a server with the [nectar recipes](https://mdsumner.github.io/nectar/)
using `--python-full --jupyter` (pending: [nectar#23](https://github.com/mdsumner/nectar/pull/23)),
then, on the server:

```bash
curl -fsSLO https://raw.githubusercontent.com/mdsumner/ga-sar-ice/main/dea-overlay.sh
sudo bash dea-overlay.sh /opt/dea && sudo chmod -R a+rX /opt/dea   # packages into /opt/gdal-py, for everyone
cp -r /opt/dea ~/dea                                              # your own copy, so outputs are writable
cd ~/dea && jupyter lab --no-browser                            # through  ssh -L 8888:localhost:8888
```

The notebooks are in `fast-ice/notebooks` and `de-sar-sample-data/demo_notebooks/tutorial_c1`.

## Where the data is

| What | Where |
|---|---|
| IW bursts, Collection 1 (20 m, tiled COGs, EPSG:3031) | STAC API `https://explorer.dev.dea.ga.gov.au/stac`, collections `ga_s1_nrb_iw_{hh,hh_hv,vv,vv_vh}_1`; each burst also has a `*_stac-item.json` beside its files in `s3://dea-public-data-dev/baseline/` |
| EW scenes (40 m, a few test sites) | one STAC-GeoParquet file: `https://dea-public-data-dev.s3.ap-southeast-2.amazonaws.com/experimental/baseline/pyrosar_gamma/ga_s1_nrb_ew_hh_hv_1_v2.parquet` |

Both are unsigned, in `ap-southeast-2`. Both are development services: expect
changes and outages.

The EW index opens directly through GDAL's Parquet driver (190 scenes,
2019-01 to 2026-05, as of 2026-11-09):

```r
ew <- "/vsicurl/https://dea-public-data-dev.s3.ap-southeast-2.amazonaws.com/experimental/baseline/pyrosar_gamma/ga_s1_nrb_ew_hh_hv_1_v2.parquet"
idx <- sf::read_sf(ew)   # warns that the list field sarard:speckle_filter_window is skipped
```

## Rough edges

- **Clashing pins.** The GA packages are installed with `--no-deps`: their pins
  clash with each other and with the image (stac-geoparquet below 0.8 for one,
  0.8 or above for the other; pystac-client below 0.9). Everything they import is
  present. Worth raising upstream.
- **pandas 3 and stac-geoparquet 0.8.3.** `stac_geoparquet.to_item_collection()`
  on the EW index fails with `TypeError: object of type 'Timestamp' has no len()`.
  Convert the date columns first:

  ```python
  for c in df.select_dtypes("datetimetz").columns:
      df[c] = df[c].astype("datetime64[ns, UTC]")
  ```

  Worth an issue on stac-geoparquet.
- **Segment Anything on CPU** is slow on the notebook's default area: use `vit_b`
  and the "fast" settings, or a GPU.

## Ideas

- The EPSG:3031 IW COGs are a good polar test case for reprojection and tiling
  work (warp-sandbox, sds).
