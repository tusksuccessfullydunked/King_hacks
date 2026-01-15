import psycopg2 

connect_ser = psycopg2.connect(
    dbname = "testing",
    user = "postgres",
    password = "qwerty123",
    host = "localhost"
)

x = connect_ser.cursor()
x.execute("SELECT * FROM users WHERE id = 1")
y = x.fetchall()

print(y)