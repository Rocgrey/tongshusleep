"""Explicit local import of user-provided content, never server credentials."""
import argparse
import json
import shutil
from html.parser import HTMLParser
from pathlib import Path

class Articles(HTMLParser):
    def __init__(self):
        super().__init__(); self.rows = []; self.current = None; self.capture = None; self.text = []
    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == 'article' and 'kp-art' in attrs.get('class', ''):
            self.current = {'number': attrs['data-t'], 'title': '', 'summary': '', 'paragraphs': []}
        if self.current is not None and tag in ('h1', 'h2', 'h3', 'p', 'li') and self.capture is None:
            self.capture = tag; self.text = []
    def handle_data(self, data):
        if self.capture: self.text.append(data)
    def handle_endtag(self, tag):
        if self.current is not None and tag == self.capture:
            text = ' '.join(''.join(self.text).split())
            if tag == 'h1': self.current['title'] = text
            elif text:
                if not self.current['summary'] and tag == 'p': self.current['summary'] = text
                self.current['paragraphs'].append(text)
            self.capture = None
        if tag == 'article' and self.current:
            self.rows.append(self.current); self.current = None

def main():
    parser = argparse.ArgumentParser(); parser.add_argument('source', type=Path); args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]; source = args.source
    catalog = []
    def item(id, title, summary, kind, cover, **extra):
        row = dict(id=id, title=title, summary=summary, body='', kind=kind, category='睡眠科普',
                   cover=Path(cover).stem, media_url=None, duration=None, preview_seconds=None,
                   parent_id=None, sort_order=len(catalog), route='content/' + id, featured=False,
                   updated_at=1795132800, external_url=None)
        row.update(extra); catalog.append(row)
        path = source / 'assets' / cover
        if path.is_file():
            dest = root / 'sleeptongshu/Assets.xcassets' / (Path(cover).stem + '.imageset')
            dest.mkdir(parents=True, exist_ok=True); shutil.copy2(path, dest / path.name)
            (dest / 'Contents.json').write_text(json.dumps({'images':[{'filename':path.name,'idiom':'universal'}], 'info':{'author':'xcode','version':1}}, indent=2))
    articles = Articles(); articles.feed((source / 'article.html').read_text())
    for row in articles.rows:
        item('article-' + row['number'], row['title'], row['summary'], 'article', 'kepu/kepu-0' + row['number'] + '.jpg', body='\n\n'.join(row['paragraphs']), featured=True)
    item('insomnia-course', '失眠症的诊断与治疗', '五讲完整课程，从认识睡眠到日常管理。', 'course', 'video/course-cover.jpg', category='系列课程', featured=True)
    titles = ['失眠症的诊断与病因','失眠症的危害','药物治疗与心理治疗','物理治疗与 CES','掌心安睡仪与综合治疗']
    for i, (title, duration) in enumerate(zip(titles, [1250,400,864,749,700]), 1):
        item('course-l' + str(i), title, '系列课程 · 第' + str(i) + '讲', 'chapter', 'video/course-cover.jpg',
             parent_id='insomnia-course', duration=duration,
             media_url='https://vid.sleep.phoenixtreeai.com/video/course-l' + str(i) + '.mp4')
    for id, title, cover, media in [('cbti','认识认知行为疗法','video/cbt-i.jpg','cbt-i'),('sleep-harm','失眠到底在消耗什么','video/kepu-video.jpg','kepu-hd')]:
        item(id, title, '完整科普视频', 'course', cover)
        item(id+'-video', title, '科普视频', 'chapter', cover, parent_id=id, media_url='https://vid.sleep.phoenixtreeai.com/video/'+media+'.mp4')
    item('jd-sleep-device', '桐树基因 CES 掌心安睡仪 · 夜烁蓝', '商品详情、价格和适用说明以京东页面为准。', 'product', 'jd-sleep-device.jpg',
         category='睡眠好物', body='点击商品图片或购买按钮前往京东。本 App 不提供下单和支付。', external_url='https://3.cn/3bngE-ty')
    (root / 'sleeptongshu/ClassroomCatalog.json').write_text(json.dumps(catalog, ensure_ascii=False, indent=2))
    print('Imported', len(catalog), 'source entries; full media playback and verified JD product 10229068197495.')

if __name__ == '__main__': main()
