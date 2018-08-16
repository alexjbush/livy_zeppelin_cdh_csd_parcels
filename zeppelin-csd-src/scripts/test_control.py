import unittest
import tempfile
import control


class TestControl(unittest.TestCase):
    def test_parse_server_properties(self):
        prop = """host.name1:livy.server.port=8998
host.name1:livy.ssl=false
host.name1:spark.version=spark2
host.name2:spark.version=spark
"""
        parsed = control.get_livy_details(prop, "spark2")
        self.assertEqual(parsed, {'livy.server.hostname': 'host.name1', 'livy.server.port': '8998', 'livy.ssl': 'false',
                                  'spark.version': 'spark2'})


if __name__ == '__main__':
    unittest.main()
