import unittest
import json
from unittest.mock import MagicMock
import numpy as np
from build_tokyo_fixed_atlas import validate, raster, reduce_rgba, mip_bytes, valid_source_manifest, CATALOG_SHAS, read_native, RESIDENTIAL_CATALOG_SHA


def triangle(height=0., color=(.5, .6, .7, 1.)):
    return np.array([[[0, height, 0, 0, 1, 0, *color], [8, height, 0, 0, 1, 0, *color], [0, height, 8, 0, 1, 0, *color]]], dtype=np.float32)


class FixedAtlasTests(unittest.TestCase):
    def test_residential_source_requires_exact_manifest(self):
        source = MagicMock()
        source.__truediv__.return_value.read_bytes.return_value = json.dumps(dict(schema=1, record_bytes=120, format='little_endian_float32_3x_XYZ_NXYZ_RGBA', configuration='lod2_full', catalog_sha256=RESIDENTIAL_CATALOG_SHA)).encode()
        with self.assertRaisesRegex(ValueError, 'residential fixed source manifest drift'):
            read_native(source, 11)

    def test_only_certified_source_catalogs(self):
        manifest = dict(schema=1, record_bytes=120, format='little_endian_float32_3x_XYZ_NXYZ_RGBA', configuration='lod2_full')
        for digest in CATALOG_SHAS:
            self.assertTrue(valid_source_manifest(dict(manifest, catalog_sha256=digest)))
        for digest in ['', '0' * 64, [], None]:
            self.assertFalse(valid_source_manifest(dict(manifest, catalog_sha256=digest)))
        valid = dict(manifest, catalog_sha256=next(iter(CATALOG_SHAS)))
        for field, value in [('schema', 2), ('record_bytes', 119), ('configuration', 'lod3_full'), ('format', 'XYZ')]:
            self.assertFalse(valid_source_manifest(dict(valid, **{field: value})))
        self.assertFalse(valid_source_manifest(None))

    def test_corners_contract(self):
        validate(triangle())
        for field, value in [(0, np.nan), (1, 2), (4, 0), (6, -1), (9, .5)]:
            broken = triangle()
            broken[0, 0, field] = value
            with self.assertRaises(ValueError): validate(broken)

    def test_ambiguous_depth_refuses(self):
        with self.assertRaises(ValueError):
            raster(np.concatenate([triangle(), triangle(color=(1, 0, 0, 1))]), 1)

    def test_disjoint_coplanar_colors_are_preserved(self):
        other = triangle(color=(1, 0, 0, 1))
        other[:, :, 0] += 12
        pixels, _ = raster(np.concatenate([triangle(), other]), 1)
        self.assertEqual(pixels[3, 3].tolist(), [128, 153, 178, 255])
        self.assertEqual(pixels[3, 15].tolist(), [255, 0, 0, 255])

    def test_highest_surface_color(self):
        data = np.concatenate([triangle(), triangle(.5, (1, 0, 0, 1))])
        pixels, info = raster(data, 1)
        interior = pixels[3, 3]
        self.assertEqual(interior.tolist(), [255, 0, 0, 255])
        self.assertEqual(info['height_range'], [0., .5])
        self.assertTrue(np.array_equal(pixels, raster(data[::-1], 1)[0]))

    def test_empty_coverage_is_not_filled(self):
        pixels, info = raster(triangle(), 1)
        self.assertTrue(np.all(pixels[:2, :, 3] == 0))
        self.assertEqual(pixels[-3, -3, 3], 0)
        self.assertGreater(info['covered_samples'], 0)

    def test_premultiplied_area_filter(self):
        samples = np.zeros((2, 2, 4), dtype=np.float32)
        samples[0, 0] = [1, 0, 0, 1]
        self.assertEqual(reduce_rgba(samples, 2)[0, 0].tolist(), [1, 0, 0, .25])

    def test_opaque_padding_keeps_rectangular_interior_and_shape(self):
        first = triangle()
        second = first.copy()
        second[0, :, [0, 2]] = np.array([[8, 8], [0, 8], [8, 0]]).T
        data = np.concatenate([first, second])
        original, _ = raster(data, 2)
        padded, info = raster(data, 2, opaque_padding=True)
        self.assertTrue(info['rectangular_coverage'] and info['opaque_rectangular_padding'])
        self.assertEqual(original.shape, padded.shape)
        self.assertTrue(np.all(padded[:, :, 3] == 255))
        self.assertTrue(np.array_equal(original[original[:, :, 3] == 255], padded[original[:, :, 3] == 255]))
        with self.assertRaises(ValueError): raster(first, 2, opaque_padding=True)

    def test_opaque_padding_rejects_subpixel_hole(self):
        import shapely
        from shapely.ops import triangulate
        from build_tokyo_fixed_atlas import opaque_rectangular_padding
        ring = shapely.box(0, 0, 8, 8).difference(shapely.box(3.99, 3.99, 4.01, 4.01))
        faces = [t for t in triangulate(ring) if ring.covers(t)]
        data = np.repeat(triangle(), len(faces), axis=0)
        for index, face in enumerate(faces):
            data[index, :, 0] = np.asarray(face.exterior.coords)[:3, 0]
            data[index, :, 2] = np.asarray(face.exterior.coords)[:3, 1]
        with self.assertRaises(ValueError):
            opaque_rectangular_padding(np.ones((4, 4, 4), dtype=np.float32), data)

    def test_resolution_clarity_refuses(self):
        for step in [0, -1, np.nan, np.inf, 3.3]:
            with self.assertRaises(ValueError): raster(triangle(), step)

    def test_mips_charge_padded_blocks(self):
        self.assertEqual(mip_bytes(4, 4), 84)
        self.assertEqual(mip_bytes(4, 4, 16), 48)
        self.assertEqual(mip_bytes(8, 4, 16), 80)


if __name__ == '__main__':
    unittest.main()
