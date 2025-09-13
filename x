# app.py
from sqlalchemy import create_engine, text
import pandas as pd
import streamlit as st
import time
from datetime import datetime
from textblob import TextBlob
import plotly.express as px

# ---------- DB CONNECTION CONFIG ----------
db_user = "postgres"
db_pass = "newpassword"   # <-- change this
db_host = "localhost"
db_port = "5432"
db_name = "db"

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

def analyze_sentiment(review_text):
    if not review_text:
        return None
    analysis = TextBlob(review_text).sentiment.polarity
    if analysis > 0.2: return "Positive"
    elif analysis < -0.2: return "Negative"
    else: return "Neutral"

def detect_priority(text):
    if not text: return "Medium"
    critical_keywords = ["poison", "expired", "harm", "unsafe", "illness", "contaminated"]
    for word in critical_keywords:
        if word in text.lower():
            return "High"
    return "Medium"

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
    q_ratings = text("SELECT rating FROM users WHERE vendor_id = :vendor_id AND rating IS NOT NULL AND complaint_text IS NOT NULL")
    q_status = text("SELECT complaint_status FROM users WHERE vendor_id = :vendor_id AND complaint_status IS NOT NULL AND complaint_text IS NOT NULL")
    with engine.connect() as conn:
        ratings = pd.read_sql(q_ratings, conn, params={"vendor_id": vendor_id})
        statuses = pd.read_sql(q_status, conn, params={"vendor_id": vendor_id})
    avg_rating = ratings['rating'].mean() if not ratings.empty else 0
    resolved_ratio = (statuses['complaint_status'].str.lower() == 'resolved').mean() if not statuses.empty else 0
    trust = round((avg_rating * 0.7) + (resolved_ratio * 100 * 0.3), 2)
    return trust, avg_rating, resolved_ratio

# ---------- Pages ----------
def page_home(users, products, vendors):
    # Custom CSS
    st.markdown("""
    <style>
        .landing-title {
            font-size: 36px;
            font-weight: 800;
            color: #2C3E50;
            text-align: center;
            margin-bottom: 10px;
        }
        .landing-sub {
            font-size: 20px;
            color: #16A085;
            text-align: center;
            margin-bottom: 30px;
        }
        .landing-section {
            background: #F8F9F9;
            border-radius: 15px;
            padding: 25px;
            margin-bottom: 20px;
            box-shadow: 0px 4px 10px rgba(0,0,0,0.1);
        }
        .feature-list li {
            font-size: 16px;
            margin-bottom: 8px;
        }
    </style>
    """, unsafe_allow_html=True)

    st.markdown("<div class='landing-title'>🏷️ Product Quality Review & Complaint Platform</div>", unsafe_allow_html=True)
    st.markdown("<div class='landing-sub'>Empowering Consumers • Ensuring Safety • Driving Accountability</div>", unsafe_allow_html=True)

    # ✅ Only count real complaints
    total = users['complaint_text'].notna().sum()
    resolved = users[users['complaint_text'].notna()]['complaint_status'].str.lower().eq('resolved').sum()
    resolved_pct = round((resolved/total*100),1) if total else 0

    col1, col2, col3 = st.columns(3)
    col1.metric("Total Complaints", total)
    col2.metric("Resolved Complaints", resolved)
    col3.metric("Resolved %", f"{resolved_pct}%")

    st.progress(int(resolved_pct))

    st.markdown("""
    <div class="landing-section">
        <h3>📖 About</h3>
        <p>
        This platform allows consumers to <b>report product complaints</b>,
        submit <b>ratings & reviews</b>, and track resolutions.
        It also verifies <b>FSSAI certification</b> and provides authorities with insights
        to enforce product quality and safety.
        </p>
    </div>
    """, unsafe_allow_html=True)

    st.markdown("""
    <div class="landing-section">
        <h3>✨ Key Features</h3>
        <ul class="feature-list">
            <li>✅ Ratings & Reviews</li>
            <li>✅ Complaint Tracking</li>
            <li>✅ FSSAI & Certification Checks</li>
            <li>✅ Analytics Dashboard</li>
            <li>✅ Mobile-First Design (PWA Ready)</li>
        </ul>
    </div>
    """, unsafe_allow_html=True)

    st.markdown("""
    <div class="landing-section">
        <h3>🎯 Our Aim</h3>
        <ul class="feature-list">
            <li>💡 Empower consumers to voice quality issues</li>
            <li>⚖️ Assist authorities with enforcement data</li>
            <li>🔒 Improve product safety & vendor accountability</li>
        </ul>
    </div>
    """, unsafe_allow_html=True)

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
    rating = st.slider("Rating (1-5)", 1, 5)
    review = st.text_area("Review (optional)")

    if st.button("Submit Complaint"):
        if not user_id.strip():
            st.error("Please enter a User ID.")
            return

        final_user_id = user_id
        if user_exists(user_id):
            ts = int(time.time())
            final_user_id = f"{user_id}_{ts}"
            st.info(f"User ID already existed — saved as: {final_user_id}")

        auto_priority = detect_priority(complaint_text)
        sentiment = analyze_sentiment(review)

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
            "complaint_priority": auto_priority,
            "complaint_date": datetime.today().date(),
            "complaint_image_url": None,
            "rating": int(rating),
            "review": review if review else None,
            "review_date": datetime.today().date(),
            "review_sentiment": sentiment
        }
        try:
            insert_complaint_row(row)
            st.success(f"✅ Complaint submitted for {product_choice} (Vendor: {vendor_choice})")
            st.info(f"Detected Priority: {auto_priority} | Review Sentiment: {sentiment}")
        except Exception as e:
            st.error(f"❌ Insert failed: {e}")

def page_track_complaints():
    st.header("📌 Complaint Tracker")
    query_user = st.text_input("Enter User ID (or part of it)")

    if st.button("Search"):
        q = text("""
            SELECT u.user_id, u.name, p.product_name, v.vendor_name,
                   u.complaint_text, u.complaint_status, u.complaint_priority,
                   u.complaint_date, u.rating, u.review_sentiment
            FROM users u
            LEFT JOIN products p ON u.product_id = p.product_id
            LEFT JOIN vendors v ON u.vendor_id = v.vendor_id
            WHERE u.complaint_text IS NOT NULL AND u.user_id ILIKE :pat
            ORDER BY u.complaint_date DESC
        """)
        with engine.connect() as conn:
            df = pd.read_sql(q, conn, params={"pat": f"%{query_user}%"})
        if not df.empty:
            st.subheader("Complaint Records")
            st.dataframe(df)
        else:
            st.warning("No complaints found.")

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
               u.complaint_date, u.rating, u.review_sentiment
        FROM users u
        LEFT JOIN products p ON u.product_id = p.product_id
        WHERE u.complaint_text IS NOT NULL AND u.vendor_id = :vendor_id
        ORDER BY u.complaint_date DESC
    """)
    with engine.connect() as conn:
        df = pd.read_sql(q, conn, params={"vendor_id": selected_vendor})

    if not df.empty:
        st.subheader("Complaints against this vendor")
        st.dataframe(df)
    else:
        st.warning("No complaints for this vendor.")

def page_analytics():
    st.header("📊 Analytics Dashboard")

    tab1, tab2, tab3, tab4 = st.tabs([
        "📦 Products", "🏭 Vendors", "⭐ Ratings", "👤 Consumers"
    ])

    # ---------------- Products Tab ----------------
    with tab1:
        st.subheader("Top Complained Products")
        top_q = text("""
            SELECT p.product_name, COUNT(*) AS total_complaints
            FROM users u
            JOIN products p ON u.product_id = p.product_id
            WHERE u.complaint_text IS NOT NULL
            GROUP BY p.product_name
            ORDER BY total_complaints DESC
            LIMIT 10
        """)
        with engine.connect() as conn:
            top_products = pd.read_sql(top_q, conn)
        if not top_products.empty:
            fig = px.bar(top_products, x="product_name", y="total_complaints",
                         title="Top Complained Products", text="total_complaints")
            st.plotly_chart(fig, use_container_width=True)
        else:
            st.info("No product complaints data available.")

    # ---------------- Vendors Tab ----------------
    with tab2:
        st.subheader("Vendors with Most Complaints")
        vendor_q = text("""
            SELECT v.vendor_name, COUNT(*) AS total_complaints
            FROM users u
            JOIN vendors v ON u.vendor_id = v.vendor_id
            WHERE u.complaint_text IS NOT NULL
            GROUP BY v.vendor_name
            ORDER BY total_complaints DESC
            LIMIT 10
        """)
        with engine.connect() as conn:
            vendor_data = pd.read_sql(vendor_q, conn)
        if not vendor_data.empty:
            fig = px.bar(vendor_data, x="vendor_name", y="total_complaints",
                         title="Top Vendors by Complaints", text="total_complaints")
            st.plotly_chart(fig, use_container_width=True)
        else:
            st.info("No vendor complaints data available.")

    # ---------------- Ratings Tab ----------------
    with tab3:
        st.subheader("Ratings Distribution")
        ratings_q = text("SELECT rating FROM users WHERE rating IS NOT NULL AND complaint_text IS NOT NULL")
        with engine.connect() as conn:
            ratings = pd.read_sql(ratings_q, conn)
        if not ratings.empty:
            fig = px.histogram(ratings, x="rating", nbins=5,
                               title="Distribution of Ratings")
            st.plotly_chart(fig, use_container_width=True)
        else:
            st.info("No ratings data available.")

    # ---------------- Consumers Tab ----------------
    with tab4:
        st.subheader("🏆 Top 5 Consumers Reporting Issues")
        reporters_q = text("""
            SELECT name, COUNT(*) AS reports
            FROM users
            WHERE complaint_text IS NOT NULL
            GROUP BY name
            ORDER BY reports DESC
            LIMIT 5
        """)
        with engine.connect() as conn:
            reporters = pd.read_sql(reporters_q, conn)
        if not reporters.empty:
            st.table(reporters)
        else:
            st.info("No consumer report data available.")

def page_raw_data(users, products, vendors):
    st.header("🔎 Raw Tables & Downloads")
    if st.checkbox("Show users"):
        st.dataframe(users)
        st.download_button("Download Users CSV", users.to_csv(index=False), "users.csv")
    if st.checkbox("Show products"):
        st.dataframe(products)
        st.download_button("Download Products CSV", products.to_csv(index=False), "products.csv")
    if st.checkbox("Show vendors"):
        st.dataframe(vendors)
        st.download_button("Download Vendors CSV", vendors.to_csv(index=False), "vendors.csv")

# ---------- Layout ----------
st.set_page_config(page_title="Product Quality Platform", layout="wide")
st.sidebar.title("Navigation")
users, products, vendors = read_tables()

page = st.sidebar.selectbox("Go to", [
    "Home","Submit Complaint","Track Complaint","Vendor Dashboard","Analytics","Raw Data"
])

if page=="Home": page_home(users, products, vendors)
elif page=="Submit Complaint": page_submit_complaint(users, products, vendors)
elif page=="Track Complaint": page_track_complaints()
elif page=="Vendor Dashboard": page_vendor_dashboard(vendors)
elif page=="Analytics": page_analytics()
elif page=="Raw Data": page_raw_data(users, products, vendors)
