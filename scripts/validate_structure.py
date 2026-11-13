"""Offline structure/contract checks. Not an Apex compiler or org validator."""
from pathlib import Path
import json,re,xml.etree.ElementTree as ET
root=Path(__file__).resolve().parents[1]
base=root/'force-app/main/default'
xmls=list(base.rglob('*.xml'))+list((root/'manifest').glob('*.xml'))
for path in xmls: ET.parse(path)
json.load(open(root/'sfdx-project.json'))
classes={path.stem:path.read_text() for path in (base/'classes').glob('*.cls')}
for name,source in classes.items():
    assert re.search(r'\bclass\s+'+name+r'\b',source),name
    assert (base/'classes'/f'{name}.cls-meta.xml').exists(),name
    for field in re.findall(r'\b\w+__c\b',source):
        assert (base/'objects'/field).exists() or list((base/'objects').glob('*/fields/'+field+'.field-meta.xml')),field
for path in (base/'lwc').rglob('*.js'):
    for class_name,method in re.findall(r'@salesforce/apex/(\w+)\.(\w+)',path.read_text()):
        assert class_name in classes,(path,class_name)
        assert re.search(r'\b'+method+r'\s*\(',classes[class_name]),(path,method)
for component in ['claimProperties','approveCommissions']:
    for extension in ['js','html','js-meta.xml']:
        assert (base/'lwc'/component/f'{component}.{extension}').exists()
print(f'PASS: {len(classes)} Apex class/metadata pairs, {len(xmls)} XML files, custom field references, LWC Apex imports and bundles.')
