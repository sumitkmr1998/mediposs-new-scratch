import pandas as pd
try:
    df = pd.read_excel(r'c:\Users\sumit\Downloads\mediposs new scratch\StkSum (2).xlsx')
    for i in range(2, 8):
        # Print actual row values separated by |
        row = df.iloc[i].values
        print(f"Row {i}: | " + " | ".join(str(x) for x in row) + " |")
except Exception as e:
    print("ERROR:", e)
