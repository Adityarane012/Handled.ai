"""
handled.ai — FastAPI application entry point.

This is the top-level app that registers all routers and provides
the /health endpoint for basic connectivity checks.
"""
import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from dotenv import load_dotenv

# Load environment variables before anything else
load_dotenv(os.path.join(os.path.dirname(__file__), ".env"))

from models.db_models import Base
from db.session import engine

from routers import auth, company

app = FastAPI(
    title="handled.ai",
    description="AI-assisted Ops module for Indian SMEs — prototype",
    version="0.1.0",
)

app.include_router(auth.router)
app.include_router(company.router)

# CORS — permissive for dev, lock down for production
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Flutter dev server, etc.
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health_check():
    """Basic health check — Phase 0 verification endpoint."""
    return {"status": "ok"}


@app.on_event("startup")
def on_startup():
    """
    Create tables on startup for dev convenience.
    In production, use Alembic migrations instead.
    """
    Base.metadata.create_all(bind=engine)
