import os
import json
import time
import pika
import requests
import logging

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger(__name__)

RABBITMQ_HOST = os.environ.get("RABBITMQ_HOST", "skywatch-rabbitmq")
RABBITMQ_USER = os.environ.get("RABBITMQ_USER", "user")
RABBITMQ_PASS = os.environ.get("RABBITMQ_PASS", "password")

GEOCODING_URL = "https://geocoding-api.open-meteo.com/v1/search"
WEATHER_URL = "https://api.open-meteo.com/v1/forecast"

WMO_CODES = {
    0: "Clear sky", 1: "Mainly clear", 2: "Partly cloudy", 3: "Overcast",
    45: "Fog", 48: "Icy fog", 51: "Light drizzle", 53: "Moderate drizzle",
    55: "Dense drizzle", 61: "Slight rain", 63: "Moderate rain", 65: "Heavy rain",
    71: "Slight snow", 73: "Moderate snow", 75: "Heavy snow",
    80: "Slight showers", 81: "Moderate showers", 82: "Violent showers",
    95: "Thunderstorm", 96: "Thunderstorm with hail", 99: "Heavy thunderstorm",
}


def get_coordinates(city: str):
    resp = requests.get(
        GEOCODING_URL,
        params={"name": city, "count": 1, "language": "en", "format": "json"},
        timeout=10,
    )
    resp.raise_for_status()
    data = resp.json()
    if not data.get("results"):
        raise ValueError(f"City '{city}' not found")
    r = data["results"][0]
    return r["latitude"], r["longitude"], r["name"], r.get("country", "")


def get_weather_data(lat: float, lon: float) -> dict:
    resp = requests.get(
        WEATHER_URL,
        params={
            "latitude": lat,
            "longitude": lon,
            "current_weather": "true",
            "hourly": "relativehumidity_2m,apparent_temperature",
            "timezone": "auto",
            "forecast_days": 1,
        },
        timeout=10,
    )
    resp.raise_for_status()
    return resp.json()


def process_request(ch, method, props, body):
    city = body.decode("utf-8").strip()
    logger.info("Processing request for: %s", city)
    try:
        lat, lon, name, country = get_coordinates(city)
        data = get_weather_data(lat, lon)
        current = data["current_weather"]
        code = int(current["weathercode"])
        result = {
            "city": name,
            "country": country,
            "latitude": round(lat, 4),
            "longitude": round(lon, 4),
            "temperature": current["temperature"],
            "windspeed": current["windspeed"],
            "weathercode": code,
            "condition": WMO_CODES.get(code, "Unknown"),
            "is_day": bool(current.get("is_day", 1)),
            "time": current["time"],
        }
        logger.info("Success: %s → %.1f°C, %s", name, result["temperature"], result["condition"])
    except Exception as exc:
        logger.error("Error for '%s': %s", city, exc)
        result = {"error": str(exc)}

    if props.reply_to:
        ch.basic_publish(
            exchange="",
            routing_key=props.reply_to,
            properties=pika.BasicProperties(correlation_id=props.correlation_id),
            body=json.dumps(result),
        )
    ch.basic_ack(delivery_tag=method.delivery_tag)


def connect_with_retry():
    credentials = pika.PlainCredentials(RABBITMQ_USER, RABBITMQ_PASS)
    params = pika.ConnectionParameters(
        host=RABBITMQ_HOST,
        credentials=credentials,
        heartbeat=600,
        blocked_connection_timeout=300,
    )
    while True:
        try:
            connection = pika.BlockingConnection(params)
            logger.info("Connected to RabbitMQ at %s", RABBITMQ_HOST)
            return connection
        except Exception as exc:
            logger.warning("RabbitMQ not ready (%s), retrying in 5s...", exc)
            time.sleep(5)


def main():
    while True:
        try:
            connection = connect_with_retry()
            channel = connection.channel()
            channel.queue_declare(queue="weather_requests", durable=True)
            channel.basic_qos(prefetch_count=1)
            channel.basic_consume(queue="weather_requests", on_message_callback=process_request)
            logger.info("Worker ready, waiting for requests...")
            channel.start_consuming()
        except Exception as exc:
            logger.error("Connection lost: %s. Reconnecting...", exc)
            time.sleep(5)


if __name__ == "__main__":
    main()
