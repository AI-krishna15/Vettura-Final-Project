import streamlit as st
import mysql.connector
import requests
from PIL import Image
import io
import datetime

# Database connection settings
def connect_to_database():
    return mysql.connector.connect(
        host='returnprocessagent.mysql.database.azure.com',
        user='Krishna',
        password='#Testing@1234',
        database='returnprocessingagent',
        ssl_ca='DigiCertGlobalRootG2.crt.pem',  # Update this path
        ssl_disabled=False
    )

# Azure Computer Vision setup
VISION_API_KEY = "FOidnEv9x6gnBa9S8fBvzGcc9N5UaOV36g8ejbZubTPaTtGRIyoHJQQJ99BCACYeBjFXJ3w3AAAFACOGV8JS"
VISION_ENDPOINT = "https://returnvisionai.cognitiveservices.azure.com/"

def analyze_product_image(image_bytes):
    headers = {
        'Ocp-Apim-Subscription-Key': VISION_API_KEY,
        'Content-Type': 'application/octet-stream'
    }
    params = {
        'visualFeatures': 'Description,Tags'
    }
    response = requests.post(f"{VISION_ENDPOINT}/analyze", headers=headers, params=params, data=image_bytes)
    response.raise_for_status()
    return response.json()

def analyze_damage_compliance(image_bytes, damage_conditions):
    headers = {
        'Ocp-Apim-Subscription-Key': VISION_API_KEY,
        'Content-Type': 'application/octet-stream'
    }
    params = {
        'visualFeatures': 'Description'
    }
    response = requests.post(f"{VISION_ENDPOINT}/analyze", headers=headers, params=params, data=image_bytes)
    response.raise_for_status()
    analysis_results = response.json()
    descriptions = analysis_results['description']['tags']
    compliance = all(any(keyword in tag for tag in descriptions) for keyword in damage_conditions.split(','))
    return compliance

def authenticate_user(email, password):
    conn = connect_to_database()
    cursor = conn.cursor(dictionary=True)
    cursor.execute("SELECT * FROM customer WHERE Email = %s AND passwords = %s", (email, password))
    user = cursor.fetchone()
    cursor.close()
    conn.close()
    return user

def fetch_product_and_order_details(user_id, product_tags):
    conn = connect_to_database()
    cursor = conn.cursor(dictionary=True)
    query = """
    SELECT p.ProductID, p.ProductName, o.OrderID, o.OrderDate, o.DeliveryDate, o.ReturnEligibleDate, p.DamagePolicyID
    FROM product AS p
    JOIN `order` AS o ON p.ProductID = o.ProductID
    WHERE o.CustomerID = %s AND p.ProductName LIKE %s
    """
    cursor.execute(query, (user_id, "%" + product_tags[0] + "%"))
    result = cursor.fetchone()
    cursor.close()
    conn.close()
    return result

def check_damage_policy(product_id):
    conn = connect_to_database()
    cursor = conn.cursor(dictionary=True)
    query = "SELECT DamagePolicyCondition FROM damagepolicy WHERE ProductID = %s"
    cursor.execute(query, (product_id,))
    policy = cursor.fetchone()
    cursor.close()
    conn.close()
    return policy

st.title("Product Return Processing System")

email = st.sidebar.text_input("Email")
password = st.sidebar.text_input("Password", type="password")
login_button = st.sidebar.button("Login")

if login_button:
    user = authenticate_user(email, password)
    if user:
        st.sidebar.success("Login successful.")
        
        uploaded_files = st.file_uploader("Upload Product Images", accept_multiple_files=True, type=['jpg', 'png', 'jpeg'])
        if uploaded_files:
            for uploaded_file in uploaded_files:
                image = Image.open(uploaded_file)
                img_bytes = io.BytesIO()
                image.save(img_bytes, format='JPEG')
                img_bytes = img_bytes.getvalue()
                
                results = analyze_product_image(img_bytes)
                tags = results['description']['tags']
                
                product_order_details = fetch_product_and_order_details(user['CustomerID'], tags)
                if product_order_details and datetime.date.today() <= product_order_details['ReturnEligibleDate']:
                    st.write(f"Product Matched: {product_order_details['ProductName']}")
                    st.write(f"Order ID: {product_order_details['OrderID']}")
                    
                    damage_policy = check_damage_policy(product_order_details['ProductID'])
                    if damage_policy:
                        st.write(f"Damage Policy: {damage_policy['DamagePolicyCondition']}")
                        if analyze_damage_compliance(img_bytes, damage_policy['DamagePolicyCondition']):
                            st.success("Return processed successfully. Your refund will be processed soon.")
                        else:
                            st.error("Return processing failed due to non-compliance with damage policy.")
                    else:
                        st.error("No damage policy found.")
                else:
                    st.error("No matching product found or return period expired.")
    else:
        st.sidebar.error("Login failed. Please check your credentials.")
