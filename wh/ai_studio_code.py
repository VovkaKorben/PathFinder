import os
import re
import xml.etree.ElementTree as ET

# Конфигурация путей
WH_LIST_FILE = r'E:\share\pf_v3\wh\wh_list.txt'
XML_FOLDER = r'C:\la_server\acis\acis_public\aCis_datapack\data\xml\spawnlist'
OUTPUT_FILE = r'E:\share\pf_v3\wh\npc_coordinates.txt'

def collect_target_ids(file_path):
    """Извлекает ID NPC из wh_list.txt (первое число в строке)"""
    target_ids = set()
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            for line in f:
                match = re.search(r'\d+', line)
                if match:
                    target_ids.add(match.group())
    except FileNotFoundError:
        print(f"Ошибка: Файл {file_path} не найден.")
    return target_ids

def process_xml_files(folder_path, target_ids):
    """Парсит XML файлы и ищет координаты нужных NPC"""
    output_lines = []
    
    if not os.path.exists(folder_path):
        print(f"Ошибка: Папка {folder_path} не существует.")
        return output_lines

    for filename in os.listdir(folder_path):
        if filename.endswith('.xml'):
            file_path = os.path.join(folder_path, filename)
            
            try:
                tree = ET.parse(file_path)
                root = tree.getroot()

                # Ищем все теги npcmaker
                for npcmaker in root.findall('.//npcmaker'):
                    maker_name = npcmaker.get('name', 'unknown_maker')
                    
                    # Внутри npcmaker ищем теги npc
                    for npc in npcmaker.findall('npc'):
                        npc_id = npc.get('id')
                        
                        if npc_id in target_ids:
                            pos_str = npc.get('pos', '')
                            # Разделяем координаты x;y;z;h
                            coords = pos_str.split(';')
                            
                            if len(coords) >= 3:
                                x, y, z = coords[0], coords[1], coords[2]
                                
                                # Формируем строку по шаблону пользователя
                                line = (f"(Loc: ''; name: ''; NpcId: {npc_id}; WhType: - 1; "
                                        f"Pos: (X: {x}; Y: {y}; Z: {z})) // {maker_name}")
                                output_lines.append(line)
                                
            except Exception as e:
                print(f"Ошибка при чтении файла {filename}: {e}")

    return output_lines

def main():
    print("Запуск парсинга...")
    
    # 1. Собираем ID
    target_ids = collect_target_ids(WH_LIST_FILE)
    if not target_ids:
        print("Список ID пуст. Проверьте wh_list.txt")
        return
    print(f"Загружено ID для поиска: {len(target_ids)}")

    # 2. Ищем в XML
    results = process_xml_files(XML_FOLDER, target_ids)

    # 3. Сохраняем результат
    if results:
        with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
            for item in results:
                f.write(item + '\n')
        print(f"Готово! Результаты сохранены в {OUTPUT_FILE}")
        print(f"Найдено совпадений: {len(results)}")
    else:
        print("Совпадений не найдено.")

if __name__ == "__main__":
    main()