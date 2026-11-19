"""Logs em JSON no stdout (o CloudWatch coleta) e métricas de negócio no formato EMF."""
import json
import logging
import os
import sys
import time


class JsonFormatter(logging.Formatter):
    def format(self, record):
        d = {
            "ts": time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(record.created)) + "Z",
            "level": record.levelname,
            "service": os.getenv("SERVICE_NAME", "app"),
            "message": record.getMessage(),
        }
        ctx = getattr(record, "ctx", None)
        if ctx:
            d.update(ctx)
        if record.exc_info:
            d["exc"] = self.formatException(record.exc_info)
        return json.dumps(d, ensure_ascii=False, default=str)


def setup():
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(os.getenv("LOG_LEVEL", "INFO"))
    for noisy in ("botocore", "boto3", "urllib3", "httpx", "httpcore"):
        logging.getLogger(noisy).setLevel(logging.WARNING)


def log(level, message, **ctx):
    logging.getLogger("app").log(level, message, extra={"ctx": ctx})


def emf(name, value=1, unit="Count", **dimensions):
    """Publica uma métrica no CloudWatch via logs (Embedded Metric Format), namespace CC."""
    dims = [list(dimensions.keys())] if dimensions else [[]]
    doc = {
        "_aws": {
            "Timestamp": int(time.time() * 1000),
            "CloudWatchMetrics": [{
                "Namespace": "CC",
                "Dimensions": dims,
                "Metrics": [{"Name": name, "Unit": unit}],
            }],
        },
        name: value,
        **dimensions,
    }
    print(json.dumps(doc), flush=True)
