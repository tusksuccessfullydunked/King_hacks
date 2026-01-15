import tensorflow as tf 
from tensorflow import keras
import cv2
import numpy as np

from tensorflow.keras.applications.efficientnet import preprocess_input

from tensorflow.keras.applications import EfficientNetB0
model = EfficientNetB0(weights='imagenet')

link = None
picutre = cv2.imread(link)
picutre = cv2.cvtColor(picutre, cv2.COLOR_BGR2RGB)
picture = cv2.resize(picutre,(224,224))
x= picutre
x= np.expand_dims(picutre, axis=0)
x = preprocess_input(x)


pred = model.predict(x)
print(pred)

from tensorflow.keras.applications.imagenet_utils import decode_predictions

for name, decs, score in decode_predictions(pred, top=1)[0]:
    print(decs, score )

picutre = cv2.putText(picutre, decs, (50,50), cv2.FONT_HERSHEY_SIMPLEX, 1, (0,0,0), 2)
cv2.imshow("picture", picutre)
cv2.waitKey(0)
cv2.destroyAllWindows()


# pass through two pictures, one is the picture the user sends, the other is the one it should look like. 
# using effiecnt, analize both pictures making a list of objects in the picutre and than comparing the two lists
# to notice the difference, than send the imformation where is needs to go. 
# 