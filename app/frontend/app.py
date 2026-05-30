import os
import uuid
import json
import pika
from flask import Flask, render_template, request

app = Flask(__name__)

RABBITMQ_HOST = os.environ.get("RABBITMQ_HOST", "skywatch-rabbitmq")
RABBITMQ_USER = os.environ.get("RABBITMQ_USER", "user")
RABBITMQ_PASS = os.environ.get("RABBITMQ_PASS", "password")
REQUEST_TIMEOUT = int(os.environ.get("REQUEST_TIMEOUT", "15"))


def get_weather(city: str) -> dict:
    credentials = pika.PlainCredentials(RABBITMQ_USER, RABBITMQ_PASS)
    params = pika.ConnectionParameters(
        host=RABBITMQ_HOST,
        credentials=credentials,
        connection_attempts=3,
        retry_delay=2,
    )
    connection = pika.BlockingConnection(params)
    channel = connection.channel()

    result_queue = channel.queue_declare(queue="", exclusive=True, auto_delete=True)
    callback_queue = result_queue.method.queue
    correlation_id = str(uuid.uuid4())
    response = {}

    def on_response(ch, method, props, body):
        if props.correlation_id == correlation_id:
            response["data"] = json.loads(body)
            ch.basic_ack(delivery_tag=method.delivery_tag)

    channel.basic_consume(queue=callback_queue, on_message_callback=on_response)
    channel.basic_publish(
        exchange="",
        routing_key="weather_requests",
        properties=pika.BasicProperties(
            reply_to=callback_queue,
            correlation_id=correlation_id,
            delivery_mode=1,
        ),
        body=city.encode(),
    )

    connection.process_data_events(time_limit=REQUEST_TIMEOUT)
    connection.close()
    return response.get("data", {"error": f"Timeout: no response in {REQUEST_TIMEOUT}s"})


@app.route("/", methods=["GET", "POST"])
def index():
    weather = None
    city = None
    error = None
    if request.method == "POST":
        city = request.form.get("city", "").strip()
        if city:
            try:
                result = get_weather(city)
                if "error" in result:
                    error = result["error"]
                else:
                    weather = result
            except Exception as exc:
                error = f"Connection error: {exc}"
    return render_template("index.html", weather=weather, city=city, error=error)


@app.route("/healthz")
def healthz():
    return {"status": "ok"}, 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)
