from flask import Flask
app = Flask(__name__)

@app.route('/Hi', methods=['GET'])
def home():
    return add_custom_headers({
        "status": "hi",
        "timestamp": datetime.now().isoformat()
    })


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5010, debug=True)