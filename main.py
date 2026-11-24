import os
from fastapi import FastAPI

API_TITLE = os.getenv("API_TITLE", "DevOps Employee Management API")
API_DESCRIPTION = os.getenv(
    "API_DESCRIPTION",
    "Application for our CI/CD learning project"
)
API_VERSION = os.getenv("API_VERSION", "1.0.0")

app = FastAPI(
    title=API_TITLE,
    description=API_DESCRIPTION,
    version=API_VERSION
)


@app.get("/")
def home():
    return {
        "message": "Welcome to DevOps Employee Management API",
        "status": "running"
    }


@app.get("/health")
def health_check():
    return {
        "status": "healthy"
    }


@app.get("/version")
def application_version():
    return {
        "application": "devops-employee-api",
        "version": API_VERSION
    }
