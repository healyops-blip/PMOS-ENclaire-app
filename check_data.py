import json

d = json.load(open('d:/hackathon_26/output_v2/case_00001.json', encoding='utf-8'))
data = d['generated_data']

print('=== 右卵巢 ===')
print(f"大小: {data['right_ovary_length']}*{data['right_ovary_width']}*{data['right_ovary_height']}mm")
print(f"基础卵泡: {data['follicle_count_right']}个")
print()
print('=== 左卵巢 ===')
print(f"大小: {data['left_ovary_length']}*{data['left_ovary_width']}*{data['left_ovary_height']}mm")
print(f"基础卵泡: {data['follicle_count_left']}个")
print()
print('原始值: 右 32*19*27, >20个; 左 29*24*30, >20个')