"""Authentication API schemas and input validation."""

from __future__ import annotations

import re
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, SecretStr, field_validator

from pomi_backend.services.security import validate_password_strength

ACCOUNT_NAME_PATTERN = re.compile(r"^[a-z0-9][a-z0-9_.-]{2,63}$")
PHONE_PATTERN = re.compile(r"^\+?[0-9]{7,20}$")


class StrictRequestModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class RegisterRequest(StrictRequestModel):
    account_name: str = Field(min_length=3, max_length=64)
    password: SecretStr = Field(min_length=8, max_length=128)
    phone_number: str | None = Field(default=None, max_length=32)

    @field_validator("account_name")
    @classmethod
    def normalize_account_name(cls, value: str) -> str:
        normalized = value.strip().lower()
        if not ACCOUNT_NAME_PATTERN.fullmatch(normalized):
            raise ValueError(
                "account_name must contain only lowercase letters, numbers, "
                "dot, underscore, or hyphen"
            )
        return normalized

    @field_validator("password")
    @classmethod
    def validate_password_complexity(cls, value: SecretStr) -> SecretStr:
        password = value.get_secret_value()
        validate_password_strength(password)
        return value

    @field_validator("phone_number")
    @classmethod
    def normalize_phone_number(cls, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = value.strip().replace(" ", "").replace("-", "")
        if not PHONE_PATTERN.fullmatch(normalized):
            raise ValueError("phone_number must contain 7 to 20 digits and may start with +")
        return normalized


class LoginRequest(StrictRequestModel):
    account_name: str = Field(min_length=3, max_length=64)
    password: SecretStr = Field(min_length=1, max_length=128)
    client_platform: str | None = Field(default=None, max_length=32)
    device_name: str | None = Field(default=None, max_length=128)

    @field_validator("account_name")
    @classmethod
    def normalize_account_name(cls, value: str) -> str:
        normalized = value.strip().replace(" ", "").replace("-", "")
        return normalized if PHONE_PATTERN.fullmatch(normalized) else value.strip().lower()


class AccountResponse(BaseModel):
    uid: str
    account_name: str
    account_type: str
    onboarding_completed: bool
    status: str
    phone_number: str | None
    phone_verified: bool


class LoginResponse(BaseModel):
    session_id: str
    token_type: Literal["Bearer"] = "Bearer"
    expires_at: datetime
    account: AccountResponse


class ErrorDetail(BaseModel):
    code: str
    message: str


class ErrorResponse(BaseModel):
    error: ErrorDetail
