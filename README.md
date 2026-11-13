
# DevOps Employee Management API

A Python FastAPI application built as part of an
end-to-end production-style DevOps CI/CD project.

## Technology Stack

- Python
- FastAPI
- Uvicorn
- Pytest
- Git
- GitHub

## API Endpoints

| Endpoint | Description |
|---|---|
| / | Application information |
| /health | Health status |
| /version | Application version |
| /docs | API documentation |

## Local Setup

Clone the repository:

    git clone YOUR_REPOSITORY_URL

Navigate into the project:

    cd devops-employee-api

Create virtual environment:

    python3 -m venv venv

Activate environment:

    source venv/bin/activate

Install dependencies:

    pip install -r requirements.txt

Run application:

    uvicorn main:app --host 0.0.0.0 --port 8000

Run tests:

    pytest -v
