Country borders: made with Natural Earth. Free vector and raster map data @ naturalearthdata.com.

The bundled `CountryBorders.bin` is derived from Natural Earth's "Admin 0 - Countries" at 1:10m, version 5.1.2, which is in the public domain:
https://www.naturalearthdata.com/about/terms-of-use/
Source file: https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/ne_10m_admin_0_countries.geojson
Source SHA-256: 239eec57ac17f100a11e2536cffc56752c318b50ae765b0918ff7aab4ce8f255

Modification: land borders simplified to within 100 m and coastlines to within 1 km, coordinates rounded to 0.0001°, and stored in a compact binary file (Tests/GenerateCountryBorders.py). Areas without a country code in the dataset are kept without a name, and eight small enclaves the dataset leaves out (such as Baarle-Hertog and Büsingen) are marked as areas where Demora can't tell.
Bundled file SHA-256: 259025bdfaa93e4e206f9d43107e12db65fa7030f43ad5df063764e1cd670229 (946,468 bytes, 240 entries, 252,669 points)

Demora uses these borders only on your iPhone, to tell which country a When & where check-in is in. Country names come from iOS. The borders are approximate and are not a statement about any disputed territory; within about 3 km of a border Demora says it can't tell.
