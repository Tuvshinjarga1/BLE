# 🏥 Health Monitor + GPS Tracking System

Энэ төсөл нь **Flutter BLE** болон **Next.js** ашиглан бүтээгдсэн реал тайм эрүүл мэндийн мониторинг систем юм. Хэрэглэгчдийн зүрхний цохилт, алхам, батарей түвшин болон **GPS байршлыг** хянаж, газрын зураг дээр харуулна.

## 🚀 Шинэ GPS функцууд

### Flutter BLE App

- ✅ **GPS байршил авах** - Хэрэглэгчийн одоогийн координатыг автоматаар авна
- ✅ **GPS тест товч** - Байршлыг шалгаж тест хийх
- ✅ **GPS мэдээлэл харуулах** - Өргөрөг, уртрагийн координатыг харуулна
- ✅ **Автомат GPS илгээх** - Health дата илгээхтэй зэрэг GPS координат илгээнэ

### Next.js Web App

- ✅ **Interactive газрын зураг** - OpenStreetMap ашиглан хэрэглэгчдийг харуулна
- ✅ **Реал тайм байршил** - GPS координаттай хэрэглэгчдийг шууд харуулна
- ✅ **Health popup** - Газрын зураг дээрх marker дээр дарахад бүх health мэдээлэл харагдана
- ✅ **GPS статистик** - Хэдэн хэрэглэгч GPS-тэй болохыг харуулна

## 📱 Flutter App ашиглах заавар

### 1. GPS зөвшөөрөл өгөх

- Програмыг эхлүүлэхэд GPS зөвшөөрөл асууна
- "Allow" дарж зөвшөөрөл өгнө үү
- Settings дээрээс Location service асаана уу

### 2. GPS тест хийх

1. **📍 GPS тест** товч дарах
2. Програм таны байршлыг олж авна
3. Координат дэлгэцэн дээр харагдана
4. Амжилттай бол веб серверт дата илгээх боломжтой

### 3. BLE device холбож GPS дата илгээх

1. **Холбох** товч дарж BLE device хайх
2. Samsung Galaxy Fit 3 эсвэл бусад device сонгох
3. Health дата автоматаар уншигдаж GPS-тэй хамт илгээгдэнэ
4. **📤 Дата илгээх** товчоор гарын авлагаар илгээх боломжтой

## 🌐 Next.js Web App

### Dashboard (http://localhost:3000/health)

- Бүх хэрэглэгчдийн health дата хүснэгт байдлаар
- GPS координат багана нэмэгдсэн
- **GPS Зураг** товчоор map руу шилжих

### GPS Map (http://localhost:3000/map)

- Интерактив газрын зураг (Улаанбаатарын төв)
- GPS координаттай хэрэглэгчдийг marker-аар харуулна
- Marker дээр дарахад:
  - Хэрэглэгчийн нэр
  - Зүрхний цохилт (өнгөөр ялгана)
  - Алхамын тоо
  - Батарей түвшин
  - GPS координат
  - Төхөөрөмжийн мэдээлэл

## 🛠️ Суулгах заавар

### Flutter BLE App

```bash
cd ble
flutter pub get
flutter run
```

### Next.js Web App

```bash
cd my-next-app
npm install
npm run dev
```

## 📊 API Endpoints

### POST /api/health

```json
{
  "userId": "device_id",
  "heartRate": 75,
  "stepCount": 8500,
  "battery": 85,
  "userName": "Хэрэглэгчийн нэр",
  "latitude": 47.9184,
  "longitude": 106.9177,
  "timestamp": "2024-01-01T12:00:00Z"
}
```

### GET /api/health?stream=true

Server-Sent Events stream for real-time updates

## 🎯 Онцлог функцууд

### GPS Tracking

- 📍 High accuracy GPS positioning
- 🔄 Автомат location updates
- 🗺️ Interactive map visualization
- 📊 Real-time location sharing

### Health Monitoring

- ❤️ Heart rate monitoring
- 👟 Step counting
- 🔋 Battery level tracking
- 📱 Multi-device support

### Real-time Features

- ⚡ Live data streaming
- 🔄 Auto refresh
- 📡 Server-Sent Events
- 🌐 Web-based dashboard

## 🧪 Test хийх

1. **Flutter app дээр GPS тест:**

   - GPS тест товч дарах
   - Координат харагдах эсэхийг шалгах

2. **Web app дээр map шалгах:**

   - http://localhost:3000/map руу очих
   - Marker харагдах эсэхийг шалгах

3. **Бүтэн integration тест:**
   - Flutter app-аас дата илгээх
   - Web dashboard-д GPS мэдээлэл харагдах
   - Map дээр шинэ marker гарах

## 🚨 Анхаарах зүйлс

- GPS зөвшөөрөл заавал шаардлагатай
- Internet холболт хэрэгтэй (map болон API-д дата илгээхэд)
- BLE device хэрэггүй ч GPS тест хийж болно
- Map ашиглахад react-leaflet package суулгах шаардлагатай

## 📞 Тусламж

GPS эсвэл map ажиллахгүй бол:

1. GPS зөвшөөрөл шалгана уу
2. Internet холболт шалгана уу
3. `npm install` дахин ажиллуулна уу
4. Browser console дээр алдаа шалгана уу
