from pydantic import BaseModel, Field, field_validator, model_validator
from datetime import datetime
from typing import Optional, Literal

class DeviceCreate(BaseModel):
    device_id: str = Field(min_length=3, max_length=50)
    name: str = Field(min_length=1, max_length=100)

class DeviceResponse(BaseModel):
    id: int
    device_id: str
    name: str
    status: str
    created_at: datetime

    class Config:
        from_attributes = True  # allow converting directly from SQLAlchemy model


class TelemetryCreate(BaseModel):
    device_id: str = Field(min_length=3, max_length=50)
    temperature: Optional[float] = None
    vibration: Optional[float] = None
    battery: Optional[float] = None
    connectivity: Optional[Literal["good", "weak", "poor"]] = None

    @field_validator("temperature")
    @classmethod
    def temperature_must_be_realistic(cls, v):
        if v is not None and (v < -50 or v > 200):
            raise ValueError("temperature out of realistic range (-50 to 200)")
        return v
    
    @field_validator("vibration")
    @classmethod
    def vibration_must_be_non_negative(cls, v):
        if v is not None and (v < 0):
            raise ValueError("vibration cannot be negative")
        return v
    
    @model_validator(mode="after")
    def at_least_one_measurement(self):
        measurements = (self.temperature, self.vibration, self.battery, self.connectivity)
        if all(m is None for m in measurements):
            raise ValueError("at least one measurement is required")
        return self

class TelemetryResponse(BaseModel):
    id: int
    device_id: str
    temperature: Optional[float]
    vibration: Optional[float]
    battery: Optional[float]
    connectivity: Optional[str]
    timestamp: datetime

    class Config:
        from_attributes = True

class AlertResponse(BaseModel):
    id: int
    device_id: str
    alert_type: str
    message: str
    resolved: bool
    created_at: datetime

    class Config:
        from_attributes = True