# API Reference

## Overview

This reference guide provides comprehensive documentation for the PRS REST API, including authentication, endpoints, request/response formats, and integration examples.

## API Base Information

### Base URL
```
https://your-domain.com/api
```

### API Version
```
Current Version: v1
Versioning: URL path (/api/v1/)
```

### Content Type
```
Content-Type: application/json
Accept: application/json
```

## Authentication

### JWT Authentication

The PRS API uses JWT (JSON Web Token) for authentication. Include the token in the Authorization header:

```http
Authorization: Bearer <jwt_token>
```

#### Login Endpoint

```http
POST /api/auth/login
Content-Type: application/json

{
  "username": "user@example.com",
  "password": "password123"
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "user": {
      "id": 1,
      "username": "user@example.com",
      "name": "John Doe",
      "role": "user",
      "department_id": 5
    },
    "expires_in": 86400
  }
}
```

#### Token Refresh

```http
POST /api/auth/refresh
Authorization: Bearer <current_token>
```

#### Logout

```http
POST /api/auth/logout
Authorization: Bearer <jwt_token>
```

## Core Endpoints

### Health Check

#### System Health
```http
GET /api/health
```

**Response:**
```json
{
  "status": "healthy",
  "timestamp": "2024-08-22T10:30:00Z",
  "version": "2.1.0",
  "database": "connected",
  "redis": "connected",
  "uptime": 86400
}
```

#### Detailed Health
```http
GET /api/health/detailed
Authorization: Bearer <jwt_token>
```

**Response:**
```json
{
  "status": "healthy",
  "components": {
    "database": {
      "status": "healthy",
      "connections": 15,
      "response_time_ms": 2.5
    },
    "redis": {
      "status": "healthy",
      "memory_usage": "45MB",
      "connected_clients": 8
    },
    "storage": {
      "ssd_usage": "65%",
      "hdd_usage": "40%"
    }
  }
}
```

### User Management

#### Get Current User
```http
GET /api/users/me
Authorization: Bearer <jwt_token>
```

#### List Users
```http
GET /api/users
Authorization: Bearer <jwt_token>
```

**Query Parameters:**
- `page` (integer): Page number (default: 1)
- `limit` (integer): Items per page (default: 20, max: 100)
- `search` (string): Search term for name/email
- `role` (string): Filter by role
- `department_id` (integer): Filter by department

**Response:**
```json
{
  "success": true,
  "data": {
    "users": [
      {
        "id": 1,
        "username": "john.doe@company.com",
        "name": "John Doe",
        "email": "john.doe@company.com",
        "role": "user",
        "department_id": 5,
        "department_name": "IT Department",
        "active": true,
        "last_login_at": "2024-08-22T09:15:00Z",
        "created_at": "2024-01-15T10:00:00Z"
      }
    ],
    "pagination": {
      "current_page": 1,
      "total_pages": 5,
      "total_items": 95,
      "items_per_page": 20
    }
  }
}
```

#### Create User
```http
POST /api/users
Authorization: Bearer <jwt_token>
Content-Type: application/json

{
  "username": "new.user@company.com",
  "name": "New User",
  "email": "new.user@company.com",
  "password": "SecurePassword123!",
  "role": "user",
  "department_id": 3
}
```

#### Update User
```http
PUT /api/users/{id}
Authorization: Bearer <jwt_token>
Content-Type: application/json

{
  "name": "Updated Name",
  "role": "admin",
  "active": true
}
```

#### Delete User
```http
DELETE /api/users/{id}
Authorization: Bearer <jwt_token>
```

### Requisitions

#### List Requisitions
```http
GET /api/requisitions
Authorization: Bearer <jwt_token>
```

**Query Parameters:**
- `page` (integer): Page number
- `limit` (integer): Items per page
- `status` (string): Filter by status (pending, approved, rejected, processing, completed)
- `department_id` (integer): Filter by department
- `user_id` (integer): Filter by user
- `date_from` (string): Start date (YYYY-MM-DD)
- `date_to` (string): End date (YYYY-MM-DD)
- `search` (string): Search in description/notes

**Response:**
```json
{
  "success": true,
  "data": {
    "requisitions": [
      {
        "id": 123,
        "requisition_number": "REQ-2024-000123",
        "description": "Office supplies for Q3",
        "status": "pending",
        "total_amount": 1250.00,
        "currency": "USD",
        "user_id": 15,
        "user_name": "Jane Smith",
        "department_id": 3,
        "department_name": "Marketing",
        "created_at": "2024-08-22T08:30:00Z",
        "updated_at": "2024-08-22T08:30:00Z",
        "items_count": 5
      }
    ],
    "pagination": {
      "current_page": 1,
      "total_pages": 12,
      "total_items": 234,
      "items_per_page": 20
    }
  }
}
```

#### Get Requisition Details
```http
GET /api/requisitions/{id}
Authorization: Bearer <jwt_token>
```

**Response:**
```json
{
  "success": true,
  "data": {
    "id": 123,
    "requisition_number": "REQ-2024-000123",
    "description": "Office supplies for Q3",
    "notes": "Urgent requirement for new office setup",
    "status": "pending",
    "total_amount": 1250.00,
    "currency": "USD",
    "user_id": 15,
    "user_name": "Jane Smith",
    "department_id": 3,
    "department_name": "Marketing",
    "created_at": "2024-08-22T08:30:00Z",
    "updated_at": "2024-08-22T08:30:00Z",
    "items": [
      {
        "id": 456,
        "description": "Laptop computers",
        "quantity": 5,
        "unit_price": 1200.00,
        "total_price": 6000.00,
        "specifications": "Dell Latitude 5520, 16GB RAM, 512GB SSD"
      }
    ],
    "approvals": [
      {
        "id": 789,
        "approver_id": 8,
        "approver_name": "Mike Johnson",
        "status": "pending",
        "level": 1,
        "created_at": "2024-08-22T08:35:00Z"
      }
    ],
    "attachments": [
      {
        "id": 101,
        "filename": "quote.pdf",
        "size": 245760,
        "uploaded_at": "2024-08-22T08:32:00Z"
      }
    ]
  }
}
```

#### Create Requisition
```http
POST /api/requisitions
Authorization: Bearer <jwt_token>
Content-Type: application/json

{
  "description": "New office equipment",
  "notes": "Required for new team members",
  "department_id": 3,
  "items": [
    {
      "description": "Laptop computers",
      "quantity": 3,
      "unit_price": 1200.00,
      "specifications": "Dell Latitude 5520"
    },
    {
      "description": "Office chairs",
      "quantity": 3,
      "unit_price": 250.00,
      "specifications": "Ergonomic with lumbar support"
    }
  ]
}
```

#### Update Requisition
```http
PUT /api/requisitions/{id}
Authorization: Bearer <jwt_token>
Content-Type: application/json

{
  "description": "Updated description",
  "notes": "Additional notes",
  "items": [
    {
      "id": 456,
      "quantity": 4,
      "unit_price": 1150.00
    }
  ]
}
```

#### Approve/Reject Requisition
```http
POST /api/requisitions/{id}/approve
Authorization: Bearer <jwt_token>
Content-Type: application/json

{
  "action": "approve",
  "comments": "Approved with budget allocation"
}
```

```http
POST /api/requisitions/{id}/reject
Authorization: Bearer <jwt_token>
Content-Type: application/json

{
  "action": "reject",
  "comments": "Insufficient budget for this quarter"
}
```

### Departments

#### List Departments
```http
GET /api/departments
Authorization: Bearer <jwt_token>
```

#### Get Department Details
```http
GET /api/departments/{id}
Authorization: Bearer <jwt_token>
```

#### Create Department
```http
POST /api/departments
Authorization: Bearer <jwt_token>
Content-Type: application/json

{
  "name": "New Department",
  "description": "Department description",
  "budget": 50000.00,
  "manager_id": 15
}
```

### Reports

#### Requisition Summary Report
```http
GET /api/reports/requisitions/summary
Authorization: Bearer <jwt_token>
```

**Query Parameters:**
- `date_from` (string): Start date (YYYY-MM-DD)
- `date_to` (string): End date (YYYY-MM-DD)
- `department_id` (integer): Filter by department
- `status` (string): Filter by status

#### Export Report
```http
GET /api/reports/requisitions/export
Authorization: Bearer <jwt_token>
```

**Query Parameters:**
- `format` (string): Export format (csv, xlsx, pdf)
- `date_from` (string): Start date
- `date_to` (string): End date

### File Management

#### Upload File
```http
POST /api/files/upload
Authorization: Bearer <jwt_token>
Content-Type: multipart/form-data

file: <binary_data>
entity_type: requisition
entity_id: 123
```

**Response:**
```json
{
  "success": true,
  "data": {
    "id": 456,
    "filename": "document.pdf",
    "original_name": "Purchase Quote.pdf",
    "size": 245760,
    "mime_type": "application/pdf",
    "url": "/api/files/456/download"
  }
}
```

#### Download File
```http
GET /api/files/{id}/download
Authorization: Bearer <jwt_token>
```

## Error Handling

### Error Response Format

```json
{
  "success": false,
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Validation failed",
    "details": [
      {
        "field": "email",
        "message": "Email is required"
      }
    ]
  }
}
```

### HTTP Status Codes

| Code | Description |
|------|-------------|
| 200 | Success |
| 201 | Created |
| 400 | Bad Request |
| 401 | Unauthorized |
| 403 | Forbidden |
| 404 | Not Found |
| 422 | Validation Error |
| 429 | Rate Limit Exceeded |
| 500 | Internal Server Error |

### Common Error Codes

| Code | Description |
|------|-------------|
| `AUTHENTICATION_REQUIRED` | Valid authentication token required |
| `INVALID_CREDENTIALS` | Username or password incorrect |
| `TOKEN_EXPIRED` | JWT token has expired |
| `INSUFFICIENT_PERMISSIONS` | User lacks required permissions |
| `VALIDATION_ERROR` | Request validation failed |
| `RESOURCE_NOT_FOUND` | Requested resource not found |
| `DUPLICATE_ENTRY` | Resource already exists |
| `RATE_LIMIT_EXCEEDED` | Too many requests |

## Rate Limiting

### Limits
- **Authenticated requests**: 1000 requests per hour
- **Authentication endpoints**: 10 requests per minute
- **File uploads**: 50 requests per hour

### Headers
```http
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 999
X-RateLimit-Reset: 1692705600
```

## Webhooks

### Webhook Events

| Event | Description |
|-------|-------------|
| `requisition.created` | New requisition created |
| `requisition.approved` | Requisition approved |
| `requisition.rejected` | Requisition rejected |
| `user.created` | New user created |
| `user.updated` | User information updated |

### Webhook Payload

```json
{
  "event": "requisition.approved",
  "timestamp": "2024-08-22T10:30:00Z",
  "data": {
    "id": 123,
    "requisition_number": "REQ-2024-000123",
    "status": "approved",
    "approver": {
      "id": 8,
      "name": "Mike Johnson"
    }
  }
}
```

## SDK Examples

### JavaScript/Node.js

```javascript
const axios = require('axios');

class PRSClient {
  constructor(baseURL, token) {
    this.client = axios.create({
      baseURL,
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json'
      }
    });
  }

  async getRequisitions(params = {}) {
    const response = await this.client.get('/requisitions', { params });
    return response.data;
  }

  async createRequisition(data) {
    const response = await this.client.post('/requisitions', data);
    return response.data;
  }

  async approveRequisition(id, comments) {
    const response = await this.client.post(`/requisitions/${id}/approve`, {
      action: 'approve',
      comments
    });
    return response.data;
  }
}

// Usage
const prs = new PRSClient('https://your-domain.com/api', 'your-jwt-token');

// Get requisitions
const requisitions = await prs.getRequisitions({
  status: 'pending',
  page: 1,
  limit: 20
});

// Create requisition
const newRequisition = await prs.createRequisition({
  description: 'Office supplies',
  department_id: 3,
  items: [
    {
      description: 'Laptops',
      quantity: 2,
      unit_price: 1200.00
    }
  ]
});
```

### Python

```python
import requests
from typing import Dict, List, Optional

class PRSClient:
    def __init__(self, base_url: str, token: str):
        self.base_url = base_url
        self.headers = {
            'Authorization': f'Bearer {token}',
            'Content-Type': 'application/json'
        }
    
    def get_requisitions(self, **params) -> Dict:
        response = requests.get(
            f'{self.base_url}/requisitions',
            headers=self.headers,
            params=params
        )
        response.raise_for_status()
        return response.json()
    
    def create_requisition(self, data: Dict) -> Dict:
        response = requests.post(
            f'{self.base_url}/requisitions',
            headers=self.headers,
            json=data
        )
        response.raise_for_status()
        return response.json()
    
    def approve_requisition(self, req_id: int, comments: str) -> Dict:
        response = requests.post(
            f'{self.base_url}/requisitions/{req_id}/approve',
            headers=self.headers,
            json={'action': 'approve', 'comments': comments}
        )
        response.raise_for_status()
        return response.json()

# Usage
prs = PRSClient('https://your-domain.com/api', 'your-jwt-token')

# Get requisitions
requisitions = prs.get_requisitions(status='pending', page=1, limit=20)

# Create requisition
new_req = prs.create_requisition({
    'description': 'Office supplies',
    'department_id': 3,
    'items': [
        {
            'description': 'Laptops',
            'quantity': 2,
            'unit_price': 1200.00
        }
    ]
})
```

---

!!! success "API Reference Complete"
    This comprehensive API reference covers all major endpoints, authentication, error handling, and integration examples for the PRS system.

!!! tip "API Testing"
    Use tools like Postman or curl to test API endpoints during development and integration.

!!! warning "Security"
    Always use HTTPS in production and keep JWT tokens secure. Never expose tokens in client-side code or logs.
