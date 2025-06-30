# Secure Data Wipe Script

**English** | [**Tiếng Việt**](#secure-data-wipe-script- phiên-bản-tiếng-việt)

---

<p align="center">
  <img src="https://img.shields.io/badge/STATUS-Operational-brightgreen" alt="Status"/>
  <img src="https://img.shields.io/badge/LICENSE-MIT-blue" alt="License"/>
  <img src="https://img.shields.io/badge/MAINTAINED-Yes-green" alt="Maintained"/>
</p>

<p align="center">
  <img src="https://img.shields.io/static/v1?label=WARNING&message=EXTREMELY%20DESTRUCTIVE&color=red&style=for-the-badge" alt="Extremely Destructive Warning"/>
</p>

## 1. Absolute Warning: Read Before Proceeding

> [!CAUTION]
> **THIS SCRIPT WILL IRREVERSIBLY DESTROY ALL DATA ON ALL DETECTED STORAGE DRIVES.**
> 
> - **NO RECOVERY:** Once executed, data recovery is physically and digitally impossible. There is no "undo" button.
> - **LEGAL LIABILITY:** You are solely and entirely responsible for the use of this script. Misuse can lead to severe civil and criminal penalties.
> - **INTENDED USE:** This script is designed **exclusively** for decommissioning servers and hardware that you are legally authorized to wipe.
>
> **DO NOT PROCEED** if you are uncertain about any of the above points. By using this script, you acknowledge that you have read, understood, and accepted all risks and responsibilities.

## 2. Legal & Compliance Disclaimer

This tool is provided "AS IS" without any warranty of any kind, express or implied. The authors and contributors are not liable for any damages or losses, direct or indirect, resulting from the use or misuse of this software.

- **Lawful Use:** You must only use this script for lawful purposes. It is strictly forbidden to use this tool to destroy data on systems you do not own, to erase evidence in a legal investigation, or to violate any data retention policies (such as GDPR, HIPAA, etc.) or contractual agreements.
- **GitHub's Policies:** This tool, as a piece of software, complies with GitHub's Acceptable Use Policies. However, using this tool for any malicious or illegal activity is a violation of GitHub's terms and the law. The responsibility for compliance rests entirely with the user.

## 3. Overview

This script provides a multi-layered, defense-grade secure data sanitization process for physical disks (HDD, SSD, NVMe). It is designed to be a final, destructive action performed on servers before they are disposed of, recycled, or repurposed, ensuring that no sensitive data can ever be recovered.

## 4. Features

- **Multi-Layered Wiping:** Combines multiple sanitization methods for maximum security.
- **Hardware-Level Erase:** Utilizes built-in ATA Secure Erase and NVMe Format commands where supported.
- **DoD 5220.22-M Standard:** Performs a government-standard wipe using `nwipe`.
- **Multi-Pass Overwrite:** Uses `dd` to overwrite the disk with random data and zeros multiple times.
- **Metadata Destruction:** Eradicates partition tables and other disk metadata.
- **Parallel Execution:** Wipes multiple disks simultaneously to save time.
- **Failsafe Mechanisms:** Includes multiple, stringent user confirmations to prevent accidental execution.
- **Comprehensive Logging:** Logs all actions and errors for auditing and verification.

## 5. Prerequisites

- A Debian-based Linux distribution (e.g., Ubuntu, Debian).
- **Root** or `sudo` privileges.
- Physical access or terminal access to the target machine.

## 6. How to Use

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/xnetvn-sst/secure-wipe-data.git
    cd your-repo-name
    ```

2.  **Review the script:**
    Open `secure_wipe_data_script.sh` and read through it to understand exactly what it does.

3.  **Execute with root privileges:**
    ```bash
    sudo bash secure_wipe_data_script.sh
    ```

4.  **Confirm the Action:**
    The script will force you through two confirmation steps to prevent accidents:
    - You must type a randomly generated string.
    - You must then type `yes` to a final confirmation prompt.
    
    If you fail either step, the script will abort safely.

5.  **Destruction Process:**
    Once confirmed, the script will proceed with the wipe. This process is **extremely time-consuming** and can take many hours or even days, depending on the size and speed of the drives.

6.  **Completion:**
    After the wipe and verification are complete, a report will be generated in `/tmp/wipe_report.txt`, and the system will automatically reboot after 60 seconds.

## 7. License

This project is licensed under the **MIT License**. See the `LICENSE` file for details.

---

## Secure Data Wipe Script (Phiên bản Tiếng Việt)

<p align="center">
  <img src="https://img.shields.io/static/v1?label=CẢNH%20BÁO&message=CỰC%20KỲ%20NGUY%20HIỂM&color=red&style=for-the-badge" alt="Cảnh báo Cực kỳ Nguy hiểm"/>
</p>

## 1. Cảnh báo Tuyệt đối: Đọc kỹ trước khi Tiếp tục

> [!CAUTION]
> **KỊCH BẢN NÀY SẼ PHÁ HỦY VĨNH VIỄN TOÀN BỘ DỮ LIỆU TRÊN TẤT CẢ Ổ ĐĨA ĐƯỢC PHÁT HIỆN.**
> 
> - **KHÔNG THỂ PHỤC HỒI:** Một khi đã thực thi, việc khôi phục dữ liệu là bất khả thi về mặt vật lý và kỹ thuật số. Không có nút "hoàn tác".
> - **TRÁCH NHIỆM PHÁP LÝ:** Bạn chịu trách nhiệm duy nhất và toàn bộ về việc sử dụng kịch bản này. Sử dụng sai mục đích có thể dẫn đến các hình phạt dân sự và hình sự nghiêm khắc.
> - **MỤC ĐÍCH SỬ DỤNG:** Kịch bản này được thiết kế **dành riêng** cho việc thải loại máy chủ và phần cứng mà bạn có thẩm quyền hợp pháp để xóa dữ liệu.
>
> **KHÔNG TIẾP TỤC** nếu bạn không chắc chắn về bất kỳ điểm nào ở trên. Bằng việc sử dụng kịch bản này, bạn xác nhận rằng bạn đã đọc, hiểu và chấp nhận mọi rủi ro và trách nhiệm.

## 2. Tuyên bố Miễn trừ Trách nhiệm Pháp lý & Tuân thủ

Công cụ này được cung cấp "NGUYÊN TRẠNG" (AS IS) mà không có bất kỳ sự bảo đảm nào, dù rõ ràng hay ngụ ý. Tác giả và những người đóng góp không chịu trách nhiệm cho bất kỳ thiệt hại hoặc tổn thất nào, dù trực tiếp hay gián tiếp, phát sinh từ việc sử dụng hoặc lạm dụng phần mềm này.

- **Sử dụng hợp pháp:** Bạn chỉ được phép sử dụng kịch bản này cho các mục đích hợp pháp. Nghiêm cấm sử dụng công cụ này để phá hủy dữ liệu trên các hệ thống bạn không sở hữu, để xóa bằng chứng trong một cuộc điều tra pháp lý, hoặc vi phạm bất kỳ chính sách lưu trữ dữ liệu nào (như GDPR, HIPAA, v.v.) hoặc các thỏa thuận hợp đồng.
- **Chính sách của GitHub:** Công cụ này, với tư cách là một phần mềm, tuân thủ Chính sách Sử dụng Chấp nhận được của GitHub. Tuy nhiên, việc sử dụng công cụ này cho bất kỳ hoạt động độc hại hoặc bất hợp pháp nào là vi phạm điều khoản của GitHub và pháp luật. Trách nhiệm tuân thủ hoàn toàn thuộc về người dùng.

## 3. Tổng quan

Kịch bản này cung cấp một quy trình vệ sinh dữ liệu an toàn đa lớp, cấp độ quân sự cho các ổ đĩa vật lý (HDD, SSD, NVMe). Nó được thiết kế như một hành động cuối cùng, có tính hủy diệt, được thực hiện trên các máy chủ trước khi chúng được thanh lý, tái chế hoặc tái sử dụng, đảm bảo rằng không có dữ liệu nhạy cảm nào có thể bị khôi phục.

## 4. Tính năng

- **Xóa đa lớp:** Kết hợp nhiều phương pháp vệ sinh để đạt độ an toàn tối đa.
- **Xóa ở cấp độ phần cứng:** Tận dụng các lệnh ATA Secure Erase và NVMe Format có sẵn khi được hỗ trợ.
- **Tiêu chuẩn DoD 5220.22-M:** Thực hiện xóa theo tiêu chuẩn chính phủ bằng `nwipe`.
- **Ghi đè nhiều lần:** Sử dụng `dd` để ghi đè lên đĩa bằng dữ liệu ngẫu nhiên và số không nhiều lần.
- **Phá hủy siêu dữ liệu (Metadata):** Xóa sạch bảng phân vùng và các siêu dữ liệu khác của đĩa.
- **Thực thi song song:** Xóa nhiều đĩa cùng lúc để tiết kiệm thời gian.
- **Cơ chế chống lỗi:** Bao gồm nhiều bước xác nhận người dùng nghiêm ngặt để ngăn chặn việc thực thi vô tình.
- **Ghi nhật ký toàn diện:** Ghi lại tất cả các hành động và lỗi để kiểm tra và xác minh.

## 5. Yêu cầu

- Một bản phân phối Linux dựa trên Debian (ví dụ: Ubuntu, Debian).
- Quyền **root** hoặc `sudo`.
- Quyền truy cập vật lý hoặc truy cập terminal vào máy chủ mục tiêu.

## 6. Cách sử dụng

1.  **Sao chép kho chứa:**
    ```bash
    git clone https://github.com/xnetvn-sst/secure-wipe-data.git
    cd your-repo-name
    ```

2.  **Xem lại kịch bản:**
    Mở tệp `secure_wipe_data_script.sh` và đọc qua để hiểu chính xác nó làm gì.

3.  **Thực thi với quyền root:**
    ```bash
    sudo bash secure_wipe_data_script.sh
    ```

4.  **Xác nhận hành động:**
    Kịch bản sẽ buộc bạn phải qua hai bước xác nhận để tránh tai nạn:
    - Bạn phải gõ một chuỗi ký tự được tạo ngẫu nhiên.
    - Sau đó, bạn phải gõ `yes` vào lời nhắc xác nhận cuối cùng.
    
    Nếu bạn thực hiện sai một trong hai bước, kịch bản sẽ hủy bỏ một cách an toàn.

5.  **Quá trình phá hủy:**
    Sau khi được xác nhận, kịch bản sẽ tiến hành xóa. Quá trình này **cực kỳ tốn thời gian** và có thể mất nhiều giờ hoặc thậm chí nhiều ngày, tùy thuộc vào dung lượng và tốc độ của ổ đĩa.

6.  **Hoàn thành:**
    Sau khi quá trình xóa và xác minh hoàn tất, một báo cáo sẽ được tạo tại `/tmp/wipe_report.txt`, và hệ thống sẽ tự động khởi động lại sau 60 giây.

## 7. Giấy phép

Dự án này được cấp phép theo **Giấy phép MIT**. Xem tệp `LICENSE` để biết chi tiết.
