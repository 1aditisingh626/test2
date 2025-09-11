# app.py
from sqlalchemy import create_engine, text
import pandas as pd
import streamlit as st
import time
from datetime import datetime

# ---------- DB CONNECTION CONFIG ----------
db_user = "postgres"
db_pass = "newpassword"   # change to your password
db_host = "localhost"
db_port = "5432"
db_name = "test2"

engine = create_engine(f"postgresql+psycopg2://{db_user}:{db_pass}@{db_host}:{db_port}/{db_name}", echo=False)

# ---------- Helpers ----------
def read_tables():
    users = pd.read_sql("SELECT * FROM users", engine)
    products = pd.read_sql("SELECT * FROM products", engine)
    vendors = pd.read_sql("SELECT * FROM vendors", engine)
    return users, products, vendors

def user_exists(user_id):
    q = text("SELECT 1 FROM users WHERE user_id = :user_id LIMIT 1")
    with engine.connect() as conn:
        res = conn.execute(q, {"user_id": user_id}).fetchone()
    return bool(res)

def insert_complaint_row(row_data):
    insert_q = text("""
        INSERT INTO users (
            user_id, name, email, state, product_id, vendor_id, product_fssai_code,
            complaint_text, complaint_status, complaint_priority, complaint_date,
            complaint_image_url, rating, review, review_date, review_sentiment
        )
        VALUES (
            :user_id, :name, :email, :state, :product_id, :vendor_id, :fssai_code,
            :complaint_text, :complaint_status, :complaint_priority, :complaint_date,
            :complaint_image_url, :rating, :review, :review_date, :review_sentiment
        )
    """)
    with engine.begin() as conn:
        conn.execute(insert_q, row_data)

def compute_vendor_trust(vendor_id):
    q_ratings = text("SELECT rating FROM users WHERE vendor_id = :vendor_id AND rating IS NOT NULL")
    q_status = text("SELECT complaint_status FROM users WHERE vendor_id = :vendor_id AND complaint_status IS NOT NULL")
    with engine.connect() as conn:
        ratings = pd.read_sql(q_ratings, conn, params={"vendor_id": vendor_id})
        statuses = pd.read_sql(q_status, conn, params={"vendor_id": vendor_id})
    avg_rating = ratings['rating'].mean() if not ratings.empty else 0
    resolved_ratio = (statuses['complaint_status'].str.lower() == 'resolved').mean() if not statuses.empty else 0
    trust = round((avg_rating * 0.7) + (resolved_ratio * 100 * 0.3), 2)
    return trust, avg_rating, resolved_ratio

# ---------- Pages ----------
def page_home(users, products, vendors):
    st.title("🏷️ Product Quality Review & Complaint Platform")
    st.subheader("Making Consumer Voice Stronger, Safer, and Transparent 🚀")

    st.markdown("""
    ### 🌍 Why this platform?
    - Consumers face unsafe or low-quality products, but there is no transparent way to raise issues.  
    - Authorities need better visibility of product safety trends and repeat offenders.  
    - Vendors should be accountable and improve based on consumer feedback.  

    ### ✨ Key Features
    - 📝 Submit complaints & product reviews  
    - 📌 Track your complaint status (Pending → In Progress → Resolved)  
    - 🏭 Vendor Dashboard with Trust Score  
    - 📊 Analytics Dashboard with trends by products, vendors, states  
    - 🔍 Verify FSSAI license codes  
    - 🤖 Chatbot (English + Hindi) for quick support  
    - 🌐 Multilingual support coming soon  

    ### 🛠 How to Use
    1. **Submit Complaint** → File complaint with product/vendor.  
    2. **Track Complaint** → Use your User ID to see complaint status.  
    3. **Vendor Dashboard** → Vendors log in to update statuses & trust score.  
    4. **Analytics** → View trends, unsafe categories, repeat offenders.  
    5. **Chatbot** → Ask about top complaints, vendor trust, state-wise stats.  

    ---
    """)

    st.markdown("### 📊 Quick Stats (Live from DB)")
    col1, col2, col3 = st.columns(3)
    col1.metric("Users/Records", len(users))
    col2.metric("Products", len(products))
    col3.metric("Vendors", len(vendors))

def page_submit_complaint(users, products, vendors):
    st.header("📝 Submit Complaint / Review")

    user_id = st.text_input("User ID (unique identifier)")
    name = st.text_input("Name")
    email = st.text_input("Email")
    state = st.text_input("State / Location")

    product_map = dict(zip(products['product_name'], products['product_id']))
    vendor_map = dict(zip(vendors['vendor_name'], vendors['vendor_id']))

    product_choice = st.selectbox("Select Product", list(product_map.keys()))
    vendor_choice = st.selectbox("Select Vendor", list(vendor_map.keys()))

    fssai_code = st.text_input("Product FSSAI Code (optional)")
    complaint_text = st.text_area("Complaint Details")
    complaint_priority = st.selectbox("Priority", ["Low", "Medium", "High"])
    rating = st.slider("Rating (1-5)", 1, 5)
    review = st.text_area("Review (optional)")

    if st.button("Submit Complaint"):
        if user_id.strip() == "":
            st.error("Please enter a User ID.")
            return

        final_user_id = user_id
        if user_exists(user_id):
            ts = int(time.time())
            final_user_id = f"{user_id}_{ts}"
            st.info(f"User ID already existed — complaint saved as new record id: {final_user_id}")

        row = {
            "user_id": final_user_id,
            "name": name if name else None,
            "email": email if email else None,
            "state": state if state else None,
            "product_id": product_map[product_choice],
            "vendor_id": vendor_map[vendor_choice],
            "fssai_code": int(fssai_code) if fssai_code.isdigit() else None,
            "complaint_text": complaint_text,
            "complaint_status": "Pending",
            "complaint_priority": complaint_priority,
            "complaint_date": datetime.today().date(),
            "complaint_image_url": None,
            "rating": int(rating),
            "review": review if review else None,
            "review_date": datetime.today().date(),
            "review_sentiment": None
        }
        try:
            insert_complaint_row(row)
            st.success(f"✅ Complaint submitted for {product_choice} (Vendor: {vendor_choice})")
        except Exception as e:
            st.error(f"❌ Insert failed: {e}")

def page_track_complaints():
    st.header("📌 Complaint Tracker")
    query_user = st.text_input("Enter the user id (or part of it)")

    if st.button("Search"):
        q = text("""
            SELECT u.user_id, u.name, p.product_name, v.vendor_name,
                   u.complaint_text, u.complaint_status, u.complaint_date, u.rating
            FROM users u
            LEFT JOIN products p ON u.product_id = p.product_id
            LEFT JOIN vendors v ON u.vendor_id = v.vendor_id
            WHERE u.user_id ILIKE :pat
            ORDER BY u.complaint_date DESC
        """)
        with engine.connect() as conn:
            df = pd.read_sql(q, conn, params={"pat": f"%{query_user}%"})
        st.dataframe(df if not df.empty else pd.DataFrame({"Message": ["No complaints found."]}))

def page_vendor_dashboard(vendors):
    st.header("🏭 Vendor Dashboard")
    vendor_choices = vendors['vendor_name'].astype(str).tolist()
    vendor_map = dict(zip(vendors['vendor_name'], vendors['vendor_id']))
    selected_vendor_name = st.selectbox("Select Vendor", vendor_choices)
    selected_vendor = vendor_map[selected_vendor_name]

    trust, avg_rating, resolved_ratio = compute_vendor_trust(selected_vendor)
    st.metric("Trust Score", trust)
    st.write(f"Average Rating: {round(avg_rating,2)}")
    st.write(f"Resolved Ratio: {round(resolved_ratio*100,2)}%")

    q = text("""
        SELECT u.user_id, u.name, p.product_name,
               u.complaint_text, u.complaint_status, u.complaint_priority,
               u.complaint_date, u.rating
        FROM users u
        LEFT JOIN products p ON u.product_id = p.product_id
        WHERE u.vendor_id = :vendor_id
        ORDER BY u.complaint_date DESC
    """)
    with engine.connect() as conn:
        df = pd.read_sql(q, conn, params={"vendor_id": selected_vendor})

    st.subheader("Complaints against this vendor")
    st.dataframe(df if not df.empty else pd.DataFrame({"Message": ["No complaints for this vendor."]}))

def page_analytics():
    st.header("📊 Analytics Dashboard")

    top_q = text("""
        SELECT p.product_name, COUNT(*) AS total_complaints
        FROM users u
        JOIN products p ON u.product_id = p.product_id
        GROUP BY p.product_name
        ORDER BY total_complaints DESC
        LIMIT 10
    """)
    with engine.connect() as conn:
        top_products = pd.read_sql(top_q, conn)

    st.subheader("Top complained products")
    st.table(top_products if not top_products.empty else "No data")

def page_powerbi():
    st.header("📈 Power BI Dashboard")
    st.write("Embedded Power BI report:")
    report_url = "https://app.powerbi.com/view?r=YOUR_REPORT_ID"  # replace with your Power BI link
    st.components.v1.iframe(report_url, height=600, width=1000)

def page_chatbot():
    st.header("🤖 Support Chatbot (English + Hindi)")
    st.write("Ask me about complaints, vendors, products, or trends!")

    # Quick reply FAQ chips
    st.markdown("### 💡 Quick Questions:")
    col1, col2, col3 = st.columns(3)
    with col1:
        if st.button("Top complaints"): st.session_state['chat_query'] = "top complaints"
    with col2:
        if st.button("Delhi me complaints kitne hain"): st.session_state['chat_query'] = "Delhi me complaints kitne hain"
    with col3:
        if st.button("Nestle vendor ka trust kya hai"): st.session_state['chat_query'] = "Nestle vendor ka trust kya hai"
    col4, col5, col6 = st.columns(3)
    with col4:
        if st.button("Maggi product ke complaints"): st.session_state['chat_query'] = "Maggi product ke complaints kitne hain"
    with col5:
        if st.button("Overview"): st.session_state['chat_query'] = "overview"
    with col6:
        if st.button("Help"): st.session_state['chat_query'] = "help"

    default_query = st.session_state.get('chat_query', "")
    q = st.text_input("Type your question:", value=default_query)

    if st.button("Ask") or default_query:
        if default_query:
            query = default_query.lower().strip()
            st.session_state['chat_query'] = ""
        else:
            query = q.lower().strip()

        # Hindi → English mappings
        if "me complaints kitne" in query or "complaints kitne hain" in query:
            state = query.replace("me complaints kitne hain", "").strip()
            query = f"complaints in {state}"
        elif "vendor ka trust" in query:
            vendor = query.replace("vendor ka trust kya hai", "").strip()
            query = f"trust vendor {vendor}"
        elif "sabse zyada complaints" in query: query = "top complaints"
        elif "overview do" in query or "sara data batao" in query: query = "overview"
        elif "product ke complaints" in query:
            prod = query.replace("product ke complaints", "").replace("kitne hain", "").strip()
            query = f"complaints for {prod}"

        # Handle queries
        if query in ["help","examples"]:
            st.markdown("Try: trust vendor Nestle | top complaints | complaints in Delhi | complaints for Maggi | overview")
        elif query.startswith("trust vendor"):
            vendor_name = query.replace("trust vendor", "").strip()
            q_vendor = text("SELECT vendor_id FROM vendors WHERE LOWER(vendor_name) LIKE :v LIMIT 1")
            with engine.connect() as conn: v = conn.execute(q_vendor, {"v": f"%{vendor_name}%"}).fetchone()
            if v:
                vid = v[0]; trust, avg_rating, resolved_ratio = compute_vendor_trust(vid)
                st.write(f"Vendor `{vendor_name}` Trust Score: {trust}")
                st.write(f"- Avg Rating: {round(avg_rating,2)} | Resolved: {round(resolved_ratio*100,2)}%")
            else: st.error("Vendor not found.")
        elif "top complaints" in query:
            top_q = text("SELECT p.product_name, COUNT(*) AS total_complaints FROM users u JOIN products p ON u.product_id = p.product_id GROUP BY p.product_name ORDER BY total_complaints DESC LIMIT 5")
            with engine.connect() as conn: st.write(pd.read_sql(top_q, conn))
        elif query.startswith("complaints in"):
            state = query.replace("complaints in", "").strip()
            with engine.connect() as conn:
                res = pd.read_sql(text("SELECT COUNT(*) AS cnt FROM users WHERE state ILIKE :s"), conn, params={"s":f"%{state}%"})
            st.write(f"Complaints in {state}: {int(res['cnt'].iloc[0])}")
        elif query.startswith("complaints for"):
            name = query.replace("complaints for", "").strip()
            q_prod = text("SELECT p.product_name, COUNT(*) AS cnt FROM users u JOIN products p ON u.product_id = p.product_id WHERE LOWER(p.product_name) LIKE :n GROUP BY p.product_name")
            with engine.connect() as conn: df = pd.read_sql(q_prod, conn, params={"n":f"%{name}%"})
            st.write(df if not df.empty else "No complaints found.")
        elif "overview" in query:
            with engine.connect() as conn:
                total = pd.read_sql("SELECT COUNT(*) AS cnt FROM users", conn).iloc[0,0]
                resolved = pd.read_sql("SELECT COUNT(*) AS cnt FROM users WHERE complaint_status ILIKE 'Resolved'", conn).iloc[0,0]
                avg_rating = pd.read_sql("SELECT AVG(rating) AS avg FROM users WHERE rating IS NOT NULL", conn).iloc[0,0]
            st.write(f"Total: {total} | Resolved: {resolved} ({round(resolved/total*100,2) if total else 0}%) | Avg Rating: {round(avg_rating,2) if avg_rating else 'N/A'}")
        else: st.error("❌ Not understood. Type `help`.")

def page_raw_data(users, products, vendors):
    st.header("🔎 Raw Tables")
    if st.checkbox("Show users"): st.dataframe(users)
    if st.checkbox("Show products"): st.dataframe(products)
    if st.checkbox("Show vendors"): st.dataframe(vendors)

# ---------- Layout ----------
st.set_page_config(page_title="Product Quality Platform", layout="wide")
st.sidebar.title("Navigation")
users, products, vendors = read_tables()

page = st.sidebar.selectbox("Go to", [
    "Home","Submit Complaint","Track Complaint","Vendor Dashboard","Analytics","Power BI Dashboard","Chatbot","Raw Data"
])

if page=="Home": page_home(users, products, vendors)
elif page=="Submit Complaint": page_submit_complaint(users, products, vendors)
elif page=="Track Complaint": page_track_complaints()
elif page=="Vendor Dashboard": page_vendor_dashboard(vendors)
elif page=="Analytics": page_analytics()
elif page=="Power BI Dashboard": page_powerbi()
elif page=="Chatbot": page_chatbot()
elif page=="Raw Data": page_raw_data(users, products, vendors)
