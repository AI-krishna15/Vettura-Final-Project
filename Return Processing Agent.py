import gradio as gr
import mysql.connector
import numpy as np
import requests
import json
from PIL import Image
from io import BytesIO
from google.cloud import vision
from google.oauth2 import service_account
from tensorflow.keras.applications.resnet50 import ResNet50, preprocess_input
from tensorflow.keras.preprocessing.image import img_to_array
from tensorflow.keras.models import Model
from sklearn.metrics.pairwise import cosine_similarity
import datetime
import os

GOOGLE_CREDENTIALS = os.getenv("GOOGLE_APPLICATION_CREDENTIALS")

if GOOGLE_CREDENTIALS:
    credentials_info = json.loads(GOOGLE_CREDENTIALS)
    credentials = service_account.Credentials.from_service_account_info(credentials_info)
    client = vision.ImageAnnotatorClient(credentials=credentials)
else:
    raise ValueError("Google Vision API credentials not found. Please add the secret in Hugging Face Spaces.")


# Database connection settings
def connect_to_database():
    try:
        return mysql.connector.connect(
            host='returnprocessagent.mysql.database.azure.com',
            user='Krishna',
            password='#Testing@1234',
            database='returnprocessingagent',
            ssl_ca='DigiCertGlobalRootCA.crt.pem'
        )
    except mysql.connector.Error as err:
        print(f"Database connection failed: {err}")
        return None

# Load ResNet50 Model for Feature Extraction
base_model = ResNet50(weights="imagenet", include_top=False, pooling="avg")
model = Model(inputs=base_model.input, outputs=base_model.output)

# Load and process image
def load_and_process_image(image_path):
    """Loads an image, resizes it, and preprocesses it for ResNet."""
    img = Image.open(image_path).convert("RGB")
    img = img.resize((224, 224))
    img_array = img_to_array(img)
    img_array = np.expand_dims(img_array, axis=0)
    img_array = preprocess_input(img_array)
    return img_array

# Extract features from an image
def extract_features(image_array):
    """Extracts feature vectors from an image using ResNet."""
    return model.predict(image_array)

# Compare two images using cosine similarity
def compare_images(uploaded_features, product_features):
    """Computes similarity score between two images."""
    similarity = cosine_similarity(uploaded_features, product_features)
    return similarity[0][0]

# Process return request
# Process return request
def process_return(email, password, uploaded_file):
    """Processes return after checking authentication, product match, return eligibility, and damage compliance."""
    conn = connect_to_database()
    if not conn:
        return "Database connection failed."

    cursor = conn.cursor(dictionary=True)

    # Authenticate User
    cursor.execute("SELECT * FROM customer WHERE Email = %s AND Passwords = %s", (email, password))
    user = cursor.fetchone()
    
    if not user:
        return "Login failed. Incorrect email or password."

    # Validate uploaded image
    if uploaded_file is None:
        return "No image file provided."

    # Extract features of uploaded image
    uploaded_features = extract_features(load_and_process_image(uploaded_file.name))

    # Fetch product data
    cursor.execute("SELECT * FROM product")
    products = cursor.fetchall()

    best_match = None
    highest_similarity = -1
    SIMILARITY_THRESHOLD = 0.7

    for product in products:
        product_images = json.loads(product["ProductImages"])

        for image_url in product_images:
            response = requests.get(image_url)
            img = Image.open(BytesIO(response.content))
            img.save("temp_product.jpg")
            product_features = extract_features(load_and_process_image("temp_product.jpg"))

            similarity = compare_images(uploaded_features, product_features)

            if similarity > highest_similarity:
                highest_similarity = similarity
                best_match = product

    # If no high-similarity match found
    if not best_match or highest_similarity < SIMILARITY_THRESHOLD:
        return "No matching product found."

    # Check if user purchased the product
    cursor.execute("""
        SELECT * FROM `order`
        WHERE CustomerID = %s AND ProductID = %s
    """, (user["CustomerID"], best_match["ProductID"]))
    order = cursor.fetchone()

    if not order:
        return f"The product '{best_match['ProductName']}' was never purchased by this user."

    # Check if product is within return eligibility window
    return_eligible_date = order["ReturnEligibleDate"]
    today = datetime.date.today()

    if today > return_eligible_date:
        return f"Return period expired. The return was eligible until {return_eligible_date}."

    # Fetch and check damage policy
    cursor.execute("SELECT DamagePolicyCondition FROM damagepolicy WHERE DamagePolicyID = %s",
                   (best_match["DamagePolicyID"],))
    damage_policy = cursor.fetchone()

    if not damage_policy:
        return "No damage policy found for this product."

    if not check_damage_policy_compliance(uploaded_file.name, damage_policy["DamagePolicyCondition"]):
        return "Return failed due to non-compliance with the damage policy."

    # Record the successful return in the returnedorders table
    try:
        cursor.execute("""
            INSERT INTO returnedorders (OrderID, CustomerID, ProductID, OrderQtyReturned, RefundAmount, ReturnedDate)
            VALUES (%s, %s, %s, %s, %s, %s)
        """, (order["OrderID"], user["CustomerID"], best_match["ProductID"], 1, product["ProductPrice"], datetime.datetime.now().strftime("%Y-%m-%d")))
        conn.commit()
    except mysql.connector.Error as err:
        print(f"Failed to insert returned order: {err}")
        return "Failed to record the return in the database."

    # Return processing successful
    return (
        f"Return processed successfully.\n"
        f"Product: {best_match['ProductName']}\n"
        f"Refund Eligible.\n"
        f"Damage Policy: {damage_policy['DamagePolicyCondition']}"
    )


# Check damage policy compliance using Google Vision API
def check_damage_policy_compliance(image_path, damage_policy_conditions):
    """Analyzes damage policy conditions with Google Vision."""
    detected_labels = analyze_product_image(image_path)
    compliance = all(any(keyword.lower() in label.lower() for label in detected_labels)
                     for keyword in damage_policy_conditions.split(","))
    return compliance

# Extract labels from an image using Google Vision API
def analyze_product_image(image_path):
    """Uses Google Vision API to detect product features and labels."""
    try:
        with open(image_path, "rb") as image_file:
            content = image_file.read()
        image = vision.Image(content=content)
        response = client.label_detection(image=image)
        labels = [label.description for label in response.label_annotations]
        return labels
    except Exception as e:
        print(f"Error analyzing image with Google Vision API: {e}")
        return []

# Gradio UI Setup
with gr.Blocks() as app:
    gr.Markdown("Product Return Processing System")
    gr.Markdown("Upload images to verify product return eligibility.")

    with gr.Row():
        with gr.Column():
            email_input = gr.Textbox(label="Email")
            password_input = gr.Textbox(label="Password", type="password")
        with gr.Column():
            file_input = gr.File(label="Upload Product Image", type="filepath", interactive=True)

    submit_button = gr.Button("Process Return")
    output = gr.Textbox(label="Results", lines=10)

    submit_button.click(
        fn=process_return,
        inputs=[email_input, password_input, file_input],
        outputs=output
    )
    
app.launch(server_name="0.0.0.0", server_port=7860)
