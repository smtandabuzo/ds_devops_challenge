"""
Unit tests for the Flask application in resources/flask_app.py
"""
import pytest
from unittest.mock import MagicMock, patch, ANY
from resources.flask_app import app as flask_app
import json
from datetime import datetime, timezone
from io import BytesIO

@pytest.fixture
def client():
    """Create a test client for the Flask application."""
    with flask_app.test_client() as client:
        with flask_app.app_context():
            yield client

@patch('resources.flask_app.get_s3_client')
def test_health_check(mock_s3_client, client):
    """Test the health check endpoint."""
    # Mock the S3 client's list_buckets method
    mock_client = MagicMock()
    mock_s3_client.return_value = mock_client
    
    # Call the health check endpoint
    response = client.get('/health')
    data = json.loads(response.data)
    
    # Assert the response
    assert response.status_code == 200
    assert data['status'] == 'healthy'
    assert data['services']['api'] == 'running'
    assert 'minio' in data['services']
    assert 'timestamp' in data
    
    # Verify the S3 client was called
    mock_client.list_buckets.assert_called_once()

@patch('resources.flask_app.get_s3_client')
def test_upload_data(mock_s3_client, client):
    """Test the data upload endpoint."""
    # Setup test data
    test_data = {"key": "value"}
    test_filename = "data_20230101_120000.json"
    
    # Create a mock S3 client and its methods
    mock_client = MagicMock()
    mock_s3_client.return_value = mock_client
    
    # Mock the put_object method to return a success response
    mock_put = MagicMock()
    mock_client.put_object = mock_put
    
    # Mock datetime to return a fixed value for consistent testing
    mock_now = datetime(2023, 1, 1, 12, 0, 0, tzinfo=timezone.utc)
    with patch('resources.flask_app.datetime', autospec=True) as mock_datetime:
        mock_datetime.now.return_value = mock_now
        mock_datetime.strftime.return_value = "20230101_120000"
        
        # Make the POST request
        response = client.post(
            '/data',
            data=json.dumps(test_data),
            content_type='application/json'
        )
    
    # Assert the response
    assert response.status_code == 201
    response_data = json.loads(response.data)
    assert response_data['message'] == 'Data uploaded successfully'
    assert response_data['filename'] == 'data_20230101_120000.json'
    
    # Verify the S3 put_object was called with the correct parameters
    mock_put.assert_called_once()
    args, kwargs = mock_put.call_args
    assert kwargs['Bucket'] == 'analytics-data'
    assert kwargs['Key'] == 'data_20230101_120000.json'
    assert json.loads(kwargs['Body']) == test_data
    assert kwargs['ContentType'] == 'application/json'

@patch('resources.flask_app.get_s3_client')
def test_upload_invalid_data(mock_s3_client, client):
    """Test the data upload endpoint with invalid data."""
    # Test with no data
    response = client.post('/data', data='', content_type='application/json')
    assert response.status_code == 400
    assert b'No data provided' in response.data
    
    # Test with invalid JSON
    response = client.post('/data', data='{invalid json', content_type='application/json')
    assert response.status_code == 400
    assert b'Invalid JSON data' in response.data

@patch('resources.flask_app.get_s3_client')
def test_list_data(mock_s3_client, client):
    """Test the data listing endpoint."""
    # Mock the S3 client response
    mock_client = MagicMock()
    mock_s3_client.return_value = mock_client
    
    # Mock the list_objects_v2 response
    mock_client.list_objects_v2.return_value = {
        'Contents': [
            {
                'Key': 'data1.json',
                'Size': 1024,
                'LastModified': datetime(2023, 1, 1, tzinfo=timezone.utc)
            },
            {
                'Key': 'data2.json',
                'Size': 2048,
                'LastModified': datetime(2023, 1, 2, tzinfo=timezone.utc)
            }
        ]
    }
    
    # Make the GET request
    response = client.get('/data')
    
    # Assert the response
    assert response.status_code == 200
    data = json.loads(response.data)
    assert data['bucket'] == 'analytics-data'
    assert len(data['files']) == 2
    assert data['files'][0]['filename'] == 'data1.json'
    assert data['files'][0]['size'] == 1024
    
    # Verify the S3 client was called
    mock_client.list_objects_v2.assert_called_once_with(Bucket='analytics-data')

@patch('resources.flask_app.get_s3_client')
def test_get_data(mock_s3_client, client):
    """Test retrieving a specific data file."""
    # Mock the S3 client response
    mock_client = MagicMock()
    mock_s3_client.return_value = mock_client
    
    # Mock the get_object response
    test_data = {'key': 'test value'}
    mock_client.get_object.return_value = {
        'Body': BytesIO(json.dumps(test_data).encode('utf-8'))
    }
    
    # Make the GET request
    response = client.get('/data/test_file.json')
    
    # Assert the response
    assert response.status_code == 200
    data = json.loads(response.data)
    assert data['filename'] == 'test_file.json'
    assert data['data'] == test_data
    
    # Verify the S3 client was called
    mock_client.get_object.assert_called_once_with(Bucket='analytics-data', Key='test_file.json')

@patch('resources.flask_app.get_s3_client')
def test_get_nonexistent_data(mock_s3_client, client):
    """Test retrieving a non-existent data file."""
    # Mock the S3 client to raise an error
    mock_client = MagicMock()
    mock_s3_client.return_value = mock_client
    
    # Mock the get_object to raise NoSuchKey error
    from botocore.exceptions import ClientError
    error_response = {'Error': {'Code': 'NoSuchKey'}}
    mock_client.get_object.side_effect = ClientError(error_response, 'get_object')
    
    # Make the GET request
    response = client.get('/data/nonexistent.json')
    
    # Assert the response
    assert response.status_code == 404
    assert b'File not found' in response.data

@patch('resources.flask_app.get_s3_client')
def test_delete_data(mock_s3_client, client):
    """Test deleting a data file."""
    # Mock the S3 client
    mock_client = MagicMock()
    mock_s3_client.return_value = mock_client
    
    # Make the DELETE request
    response = client.delete('/data/test_file.json')
    
    # Assert the response
    assert response.status_code == 200
    data = json.loads(response.data)
    assert data['message'] == 'File deleted successfully'
    assert data['filename'] == 'test_file.json'
    
    # Verify the S3 client was called
    mock_client.delete_object.assert_called_once_with(Bucket='analytics-data', Key='test_file.json')

@patch('resources.flask_app.get_s3_client')
def test_health_check_error(mock_s3_client, client):
    """Test health check when MinIO is not available."""
    # Mock the S3 client to raise an error
    mock_client = MagicMock()
    mock_s3_client.return_value = mock_client
    mock_client.list_buckets.side_effect = Exception("Connection error")
    
    # Make the GET request
    response = client.get('/health')
    
    # Assert the response
    assert response.status_code == 503
    data = json.loads(response.data)
    assert data['status'] == 'unhealthy'
    assert data['services']['minio'] == 'disconnected'

# Add more test cases as needed
if __name__ == '__main__':
    pytest.main()
