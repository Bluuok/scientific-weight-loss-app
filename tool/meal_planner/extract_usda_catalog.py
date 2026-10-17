import csv, io, json, zipfile, pathlib, hashlib

root = pathlib.Path(__file__).resolve().parents[2]
z = zipfile.ZipFile(root / '.local/usda.zip')
def rows(name):
    return csv.DictReader(io.TextIOWrapper(z.open(next(n for n in z.namelist() if n.endswith('/'+name))), encoding='utf-8'))
food_rows = {r['fdc_id']:r for r in rows('food.csv')}
selected = [
 ('oats','169705','燕麦','grain','干重'),('rice','169703','糙米','grain','干重'),
 ('milk','170872','低脂牛奶','dairy','即饮重量'),('egg','171287','鸡蛋','protein','去壳生重'),
 ('chicken','171077','去皮鸡胸肉','protein','生重'),('beef','171790','瘦牛肉糜（95%瘦）','protein','生重'),
 ('fish','171955','鳕鱼','protein','生重'),('tofu','172475','钙凝固硬豆腐','protein','生重'),
 ('broccoli','170379','西兰花','vegetable','生重'),('lettuce','169249','生菜','vegetable','生重'),
 ('carrot','170393','胡萝卜','vegetable','生重'),('cabbage','169975','卷心菜','vegetable','生重'),
 ('tomato','170457','番茄','vegetable','生重'),('cucumber','168409','黄瓜','vegetable','生重'),
 ('spinach','168462','菠菜','vegetable','生重'),('mushroom','169251','白蘑菇','vegetable','生重'),
 ('apple','171688','苹果','fruit','带皮可食部生重'),('banana','173944','香蕉','fruit','去皮生重'),
 ('orange','169097','橙子','fruit','去皮生重'),('pear','169118','梨','fruit','可食部生重'),
 ('potato','170026','土豆','starch','生重'),('sweet_potato','168482','红薯','starch','生重'),
 ('walnut','170187','核桃仁','nuts','可食部生重'),('oil','171413','橄榄油','oil','实际用量'),
 ('salt','173468','普通食盐','salt','实际用量'),('soybean','169282','毛豆仁','protein','生重')]
ids = {x[1] for x in selected}
nutrients={i:{} for i in ids}
mapping={'1008':'kcal','1003':'protein','1093':'sodium','1005':'carbs','1004':'fat','1079':'fiber'}
for r in rows('food_nutrient.csv'):
    if r['fdc_id'] in ids and r['nutrient_id'] in mapping:
        nutrients[r['fdc_id']][mapping[r['nutrient_id']]]=float(r['amount'])
foods=[]
for key,fdc,name,group,state in selected:
    assert len(nutrients[fdc])==6, (key,nutrients[fdc])
    foods.append(dict(id=key,fdc_id=fdc,name=name,group=group,state=state,
      source_description=food_rows[fdc]['description'],
      source_url=f'https://fdc.nal.usda.gov/food-details/{fdc}/nutrients',**nutrients[fdc]))
recipes=[]
def recipe(key,name,ingredients,simple=False,slots=None,method=None):
    recipes.append(dict(id=key,name=name,ingredients=ingredients,simple=simple,
      slots=slots or ['lunch','dinner'],
      method=method or '糙米按干重称量后煮熟；肉和蔬菜称生重。肉类彻底蒸熟或煮熟，蔬菜焯熟；全部食用油、盐按所列重量加入，不另加酱料。水果直接食用。'))
for i,fruit in enumerate(['apple','banana','orange']):
    recipe(f'b{i}', ['苹果燕麦早餐','香蕉燕麦早餐','香橙燕麦早餐'][i],
      dict(oats=80,milk=300,egg=60,walnut=15,**{fruit:200}),slots=['breakfast'],
      method='燕麦按干重称量，用水煮熟；鸡蛋称去壳生重后煮熟；牛奶直接饮用。搭配所列水果和核桃，不额外加糖、油、盐。')
for i,(protein,grams,veg) in enumerate([('chicken',150,'broccoli'),('beef',150,'cabbage'),('fish',180,'spinach'),('tofu',180,'tomato'),('egg',150,'mushroom')]):
    recipe(f's{i}', ['鸡胸西兰花简洁餐','瘦牛肉卷心菜简洁餐','清蒸鳕鱼菠菜简洁餐','豆腐番茄简洁餐','鸡蛋蘑菇简洁餐'][i],
      dict(rice=90,oil=10,salt=1,lettuce=100,**{protein:grams,veg:200}),simple=True)
for i,(protein,grams,veg,fruit) in enumerate([('chicken',130,'carrot','orange'),('fish',180,'tomato','apple'),('tofu',180,'cabbage','pear'),('beef',130,'broccoli','banana'),('egg',120,'mushroom','apple')]):
    recipe(f'd{i}', ['鸡肉糙米蔬菜餐','鳕鱼番茄糙米餐','豆腐卷心菜糙米餐','牛肉西兰花糙米餐','鸡蛋蘑菇糙米餐'][i],
      dict(rice=100,oil=12,salt=1,cucumber=150,**{protein:grams,veg:150,fruit:150}))
data=dict(version='USDA-SR-Legacy-2018-local-v1',basis='per 100g edible portion; sodium mg, other nutrients g except kcal',
  download_url='https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_csv_2018-04.zip',
  archive_sha256=hashlib.sha256((root/'.local/usda.zip').read_bytes()).hexdigest(),foods=foods,recipes=recipes)
out=root/'assets/meal_planner/catalog.json'
out.parent.mkdir(parents=True,exist_ok=True)
out.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(f'Extracted {len(foods)} foods / {len(recipes)} recipes from USDA official CSV')
