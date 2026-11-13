
from fastapi import FastAPI

app = FastAPI(
    title="DevOps Employee Management API",
    description="Application for our CI/CD learning project",
    version="1.0.0"
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
        "version": "1.0.0"
    }
