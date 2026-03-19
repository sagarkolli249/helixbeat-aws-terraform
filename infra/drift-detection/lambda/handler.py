"""
HelixBeat – Terraform Drift Detection Lambda
Slide 4: EventBridge (daily) → Lambda → terraform plan --detailed-exitcode
Exit code 2 = drift → SNS alert → Teams + PagerDuty → Jira ticket auto-created.

The Lambda itself triggers CodeBuild (which has Terraform installed) to run
the plan, then reads the exit code from the CodeBuild log.
"""
import json
import os
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

CODEBUILD_PROJECT = os.environ["CODEBUILD_PROJECT_NAME"]
SNS_TOPIC_ARN     = os.environ["SNS_TOPIC_ARN"]
S3_BUCKET         = os.environ["S3_DRIFT_BUCKET"]
ENVIRONMENTS      = os.environ.get("ENVIRONMENTS", "dev-us,dev-in,staging-us,staging-in").split(",")
GITHUB_ORG        = os.environ.get("GITHUB_ORG", "helixbeat")

codebuild = boto3.client("codebuild")
sns       = boto3.client("sns")
s3        = boto3.client("s3")

def lambda_handler(event, context):
    logger.info("Starting drift detection for: %s", ENVIRONMENTS)
    results = {}

    for env in ENVIRONMENTS:
        logger.info("Checking drift for environment: %s", env)
        try:
            build = codebuild.start_build(
                projectName=CODEBUILD_PROJECT,
                environmentVariablesOverride=[
                    {"name": "TF_ENV", "value": env, "type": "PLAINTEXT"},
                    {"name": "ACTION",  "value": "drift-check", "type": "PLAINTEXT"},
                ],
                sourceVersion="main",
            )
            build_id = build["build"]["id"]
            results[env] = {"build_id": build_id, "status": "STARTED"}
            logger.info("Started CodeBuild %s for %s", build_id, env)
        except Exception as e:
            logger.error("Failed to start build for %s: %s", env, e)
            results[env] = {"error": str(e), "status": "FAILED_TO_START"}

    # Save run record to S3
    record = {
        "run_at": datetime.utcnow().isoformat() + "Z",
        "environments": results,
    }
    s3.put_object(
        Bucket=S3_BUCKET,
        Key=f"drift-runs/{datetime.utcnow().strftime('%Y/%m/%d')}/run.json",
        Body=json.dumps(record, indent=2),
        ContentType="application/json",
    )

    return {"statusCode": 200, "body": json.dumps(results)}


def handle_codebuild_event(event, context):
    """
    Triggered by EventBridge when a CodeBuild drift-check build completes.
    Reads the exit code from environment variables set by the buildspec.
    """
    detail = event.get("detail", {})
    build_status = detail.get("build-status")
    env = next(
        (e["value"] for e in detail.get("additional-information", {}).get("environment", {}).get("environment-variables", [])
         if e["name"] == "TF_ENV"),
        "unknown"
    )

    if build_status == "FAILED":
        # CodeBuild exits non-zero on drift (exit code 2)
        message = {
            "type": "drift-detected",
            "environment": env,
            "build_id": detail.get("build-id"),
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "action_required": "Review Terraform plan diff and apply if approved",
            "drift_report_s3": f"s3://{S3_BUCKET}/drift/{env}/{datetime.utcnow().strftime('%Y-%m-%d')}-drift.txt",
        }
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=f"[DRIFT] Terraform drift detected: {env}",
            Message=json.dumps(message, indent=2),
        )
        logger.warning("Drift detected in %s — SNS notification sent", env)
    elif build_status == "SUCCEEDED":
        logger.info("No drift in %s", env)
