"""
Data Analytics Hub - S3 Data Service
A simple Flask application that interacts with Minio S3 storage
"""

import os
import json
from datetime import datetime, timezone
from flask import Flask, jsonify, request
import boto3
from botocore.exceptions import ClientError

app = Flask(__name__)

# Configuration from environment variables
def get_env_var(name, default=None, file_path=None):
    """Get environment variable or from file if specified"""
    value = os.getenv(name)
    if value is not None:
        return value
    
    file_var = f"{name}_FILE"
    file_path = os.getenv(file_var, file_path)
    if file_path and os.path.exists(file_path):
        with open(file_path, 'r') as f:
            return f.read().strip()
    
    return default

# Read configuration with fallback to file-based secrets
MINIO_ACCESS_KEY = get_env_var('MINIO_ACCESS_KEY', 'minioadmin', '/run/secrets/MINIO_ACCESS_KEY')
MINIO_SECRET_KEY = get_env_var('MINIO_SECRET_KEY', 'minioadmin', '/run/secrets/MINIO_SECRET_KEY')
MINIO_ENDPOINT = get_env_var('MINIO_ENDPOINT', 'minio:9000')
BUCKET_NAME = get_env_var('BUCKET_NAME', 'analytics-data')


# Initialize S3 client as None
_s3_client = None

def get_s3_client():
    """
    Get or create an S3 client for Minio with connection pooling
    Uses a singleton pattern to reuse the client across requests
    """
    global _s3_client
    if _s3_client is None:
        _s3_client = boto3.client(
            's3',
            endpoint_url=f'http://{MINIO_ENDPOINT}',
            aws_access_key_id=MINIO_ACCESS_KEY,
            aws_secret_access_key=MINIO_SECRET_KEY,
            region_name='us-east-1',
            config=boto3.session.Config(
                max_pool_connections=100,  # Increased connection pool size
                retries={
                    'max_attempts': 3,
                    'mode': 'standard'
                },
                connect_timeout=5,
                read_timeout=30
            )
        )
        
        # Ensure bucket exists
        try:
            _s3_client.head_bucket(Bucket=BUCKET_NAME)
        except ClientError:
            _s3_client.create_bucket(Bucket=BUCKET_NAME)
            print(f"Created bucket: {BUCKET_NAME}")
    
    return _s3_client


@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint that verifies MinIO connectivity"""
    try:
        # Check if we can connect to MinIO
        s3 = get_s3_client()
        s3.list_buckets()
        
        return jsonify({
            'status': 'healthy',
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'services': {
                'minio': 'connected',
                'database': 'not_used',
                'api': 'running'
            },
            'endpoint': f'http://{MINIO_ENDPOINT}'
        }), 200
    except Exception as e:
        return jsonify({
            'status': 'unhealthy',
            'error': str(e),
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'services': {
                'minio': 'disconnected',
                'database': 'not_used',
                'api': 'running'
            },
            'endpoint': f'http://{MINIO_ENDPOINT}'
        }), 503

@app.route('/data', methods=['POST'])
def upload_data():
    """Upload data to S3 storage"""
    try:
        if not request.data:
            return jsonify({'error': 'No data provided'}), 400
            
        try:
            data = request.get_json()
            if data is None:
                raise ValueError("Invalid JSON data")
        except Exception as e:
            return jsonify({'error': 'Invalid JSON data'}), 400
        
        # Generate a unique filename
        timestamp = datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')
        filename = f'data_{timestamp}.json'
        
        # Upload to S3
        s3_client = get_s3_client()
        s3_client.put_object(
            Bucket=BUCKET_NAME,
            Key=filename,
            Body=json.dumps(data),
            ContentType='application/json'
        )
        
        return jsonify({
            'message': 'Data uploaded successfully',
            'filename': filename,
            'bucket': BUCKET_NAME
        }), 201
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/data', methods=['GET'])
def list_data():
    """List all data files in S3 storage"""
    try:
        s3_client = get_s3_client()
        response = s3_client.list_objects_v2(Bucket=BUCKET_NAME)
        
        files = []
        if 'Contents' in response:
            for obj in response['Contents']:
                files.append({
                    'filename': obj['Key'],
                    'size': obj['Size'],
                    'last_modified': obj['LastModified'].isoformat()
                })
        
        return jsonify({
            'bucket': BUCKET_NAME,
            'count': len(files),
            'files': files
        }), 200
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/data/<filename>', methods=['GET'])
def get_data(filename):
    """Retrieve a specific data file from S3 storage"""
    try:
        s3_client = get_s3_client()
        response = s3_client.get_object(Bucket=BUCKET_NAME, Key=filename)
        data = json.loads(response['Body'].read().decode('utf-8'))
        
        return jsonify({
            'filename': filename,
            'data': data
        }), 200
        
    except ClientError as e:
        if e.response['Error']['Code'] == 'NoSuchKey':
            return jsonify({'error': 'File not found'}), 404
        return jsonify({'error': str(e)}), 500
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/data/<filename>', methods=['DELETE'])
def delete_data(filename):
    """Delete a specific data file from S3 storage"""
    try:
        s3_client = get_s3_client()
        s3_client.delete_object(Bucket=BUCKET_NAME, Key=filename)
        
        return jsonify({
            'message': 'File deleted successfully',
            'filename': filename
        }), 200
    except Exception as e:
        return jsonify({'error': str(e)}), 500

# Health check endpoint is already defined above

@app.route('/')
def index():
    """Root endpoint with API information"""
    return jsonify({
        'name': 'Data Analytics Hub - S3 Data Service',
        'version': '1.0.0',
        'endpoints': [
            {'path': '/', 'methods': ['GET'], 'description': 'API information'},
            {'path': '/health', 'methods': ['GET'], 'description': 'Health check'},
            {'path': '/upload', 'methods': ['POST'], 'description': 'Upload data'},
            {'path': '/data', 'methods': ['GET'], 'description': 'List all data'},
            {'path': '/data/<filename>', 'methods': ['GET'], 'description': 'Get specific data'},
            {'path': '/data/<filename>', 'methods': ['DELETE'], 'description': 'Delete specific data'}
        ]
    })

def ensure_bucket_exists():
    """Ensure the S3 bucket exists"""
    try:
        s3 = get_s3_client()
        s3.create_bucket(Bucket=BUCKET_NAME)
    except Exception as e:
        # Bucket likely already exists
        pass

if __name__ == '__main__':
    # Ensure bucket exists on startup
    ensure_bucket_exists()
    
    # Run the application
    app.run(host='0.0.0.0', port=5000, debug=False)