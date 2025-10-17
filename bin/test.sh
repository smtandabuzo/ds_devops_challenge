#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Check if Python is installed
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}❌ Python 3 is required but not installed.${NC}"
    exit 1
fi

# Check if pytest is installed
if ! python3 -m pytest --version &> /dev/null; then
    echo -e "Installing pytest..."
    pip3 install --user pytest pytest-cov
fi

# Create test directory if it doesn't exist
TEST_DIR="$PROJECT_ROOT/tests"
mkdir -p "$TEST_DIR"

# Create a basic test file if it doesn't exist
TEST_FILE="$TEST_DIR/test_app.py"
if [ ! -f "$TEST_FILE" ]; then
    cat > "$TEST_FILE" << 'EOL'
import unittest
from unittest.mock import patch, MagicMock
import sys
import os

# Add the resources directory to the path
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'resources'))

class TestApp(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Set up test environment variables
        os.environ['MINIO_ACCESS_KEY'] = 'test_access_key'
        os.environ['MINIO_SECRET_KEY'] = 'test_secret_key'
        os.environ['MINIO_ENDPOINT'] = 'localhost:9000'
        os.environ['BUCKET_NAME'] = 'test-bucket'

    def test_health_check(self):
        # Mock the Flask app and its dependencies
        with patch('flask.Flask'), \
             patch('boto3.client') as mock_boto3, \
             patch('os.getenv') as mock_getenv:
            
            # Mock environment variables
            mock_getenv.side_effect = lambda x, default=None: {
                'MINIO_ACCESS_KEY': 'test',
                'MINIO_SECRET_KEY': 'test',
                'MINIO_ENDPOINT': 'minio:9000',
                'BUCKET_NAME': 'test-bucket'
            }.get(x, default)
            
            # Import the app after setting up mocks
            from flask_app import app, get_s3_client
            
            # Create a test client
            with app.test_client() as client:
                # Test health check endpoint
                response = client.get('/health')
                self.assertEqual(response.status_code, 200)
                self.assertIn(b'status', response.data)

if __name__ == '__main__':
    unittest.main()
EOL
    echo -e "Created test file at $TEST_FILE"
fi

# Run the tests
echo -e "Running tests..."
cd "$PROJECT_ROOT"
if ! python3 -m pytest -v --cov=resources --cov-report=term-missing "$TEST_DIR"; then
    echo -e "${RED}❌ Tests failed!${NC}"
    exit 1
fi

echo -e "${GREEN}✅ All tests passed!${NC}"
exit 0
