"""
Data Analytics Hub - S3 Data Service
A simple Flask application that interacts with Minio S3 storage
"""

import os
import json
from datetime import datetime
from flask import Flask, jsonify, request
import boto3
from botocore.exceptions import ClientError

app = Flask(__name__)

# Configuration from environment variables
MINIO_ACCESS_KEY = os.getenv('MINIO_ACCESS_KEY', 'minioadmin')
MINIO_SECRET_KEY = os.getenv('MINIO_SECRET_KEY', 'minioadmin')
MINIO_ENDPOINT = os.getenv('MINIO_ENDPOINT', 'minio:9000')
BUCKET_NAME = os.getenv('BUCKET_NAME', 'analytics-data')


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
        s3_client.head_bucket(Bucket=BUCKET_NAME)
    except ClientError:
        s3_client.create_bucket(Bucket=BUCKET_NAME)
        print(f"Created bucket: {BUCKET_NAME}")


@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.utcnow().isoformat(),
        'service': 'data-analytics-service'
    }), 200


@app.route('/storage/health', methods=['GET'])
def storage_health():
    """Check if we can connect to Minio"""
    try:
        s3_client = get_s3_client()
        s3_client.list_buckets()
        return jsonify({
            'status': 'healthy',
            'storage': 'connected',
            'endpoint': MINIO_ENDPOINT
        }), 200
    except Exception as e:
        return jsonify({
            'status': 'unhealthy',
            'storage': 'disconnected',
            'error': str(e)
        }), 503


@app.route('/data', methods=['POST'])
def upload_data():
    """Upload data to S3 storage"""
    try:
        data = request.get_json()
        
        if not data:
            return jsonify({'error': 'No data provided'}), 400
        
        # Generate a unique filename
        timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
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


@app.route('/', methods=['GET'])
def index():
    """Root endpoint with API information"""
    return jsonify({
        'service': 'Data Analytics Hub - S3 Data Service',
        'version': '1.0.0',
        'endpoints': {
            'health': '/health',
            'storage_health': '/storage/health',
            'upload_data': 'POST /data',
            'list_data': 'GET /data',
            'get_data': 'GET /data/<filename>',
            'delete_data': 'DELETE /data/<filename>'
        }
    }), 200


if __name__ == '__main__':
    # Ensure bucket exists on startup
    try:
        ensure_bucket_exists()
    except Exception as e:
        print(f"Warning: Could not ensure bucket exists: {e}")
    
    # Run the application
    app.run(host='0.0.0.0', port=5000, debug=False)