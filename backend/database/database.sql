
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE TABLE tai_khoan (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    username text NOT NULL UNIQUE,
    password_hash text NOT NULL, 
    role text NOT NULL CHECK (
        role IN (
            'admin',
            'training',
            'accountant',
            'hr',
            'teacher',
            'student'
        )
    ),
    account_status text NOT NULL DEFAULT 'active' CHECK (
        account_status IN ('active', 'locked')
    ),
    must_change_password boolean NOT NULL DEFAULT true, 
    failed_login_count int NOT NULL DEFAULT 0,
    last_login_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE hoc_vien (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id bigint NOT NULL UNIQUE REFERENCES tai_khoan (id),
    student_code text NOT NULL UNIQUE,
    full_name text NOT NULL,
    date_of_birth date,
    gender text CHECK (
        gender IN ('male', 'female', 'other')
    ),
    phone text,
    email text,
    address text,
    guardian_name text, -- học viên nhỏ tuổi
    guardian_phone text,
    guardian_relation text,
    has_old_debt boolean NOT NULL DEFAULT false, -- cờ "còn nợ cũ": chặn đăng ký lộ trình mới
    status text NOT NULL DEFAULT 'active' CHECK (
        status IN ('active', 'inactive')
    ),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_hoc_vien_phone ON hoc_vien (phone);
-- kiểm tra trùng hồ sơ ở tầng ứng dụng
CREATE INDEX idx_hoc_vien_email ON hoc_vien (email);

CREATE TABLE nhan_vien (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id bigint NOT NULL UNIQUE REFERENCES tai_khoan (id),
    employee_code text NOT NULL UNIQUE,
    full_name text NOT NULL,
    date_of_birth date,
    gender text CHECK (
        gender IN ('male', 'female', 'other')
    ),
    phone text,
    email text,
    address text,
    id_number text, -- CCCD
    employee_type text NOT NULL CHECK (
        employee_type IN (
            'admin',
            'teacher',
            'training',
            'accountant',
            'hr'
        )
    ),
    status text NOT NULL DEFAULT 'active' CHECK (
        status IN (
            'active',
            'resigning',
            'resigned_pending_settlement',
            'resigned_settled'
        )
    ),
    hire_date date,
    resign_date date,
    resign_reason text,
    base_salary numeric(14, 2), -- lương cơ bản (nhân viên lương cố định)
    salary_coefficient numeric(4, 2) DEFAULT 1 CHECK (salary_coefficient >= 1), -- hệ số (giáo viên)
    degree text, -- bằng cấp, chứng chỉ (giáo viên)
    specialty text, -- chuyên môn (giáo viên)
    has_company_debt boolean NOT NULL DEFAULT false, -- nợ trung tâm sau quyết toán nghỉ việc
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_nhan_vien_loai_trang_thai ON nhan_vien (employee_type, status);

CREATE TABLE lo_trinh ( -- lộ trình
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code text NOT NULL UNIQUE, -- VSTEP, TOEIC, IELTS, GIAOTIEP
    name text NOT NULL,
    program_type text NOT NULL CHECK (
        program_type IN (
            'certificate',
            'communication'
        )
    ),
    description text,
    is_active boolean NOT NULL DEFAULT true
);

CREATE TABLE khoa_hoc ( -- khóa = một giai đoạn của lộ trình
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    program_id bigint NOT NULL REFERENCES lo_trinh (id),
    code text NOT NULL UNIQUE,
    name text NOT NULL,
    stage_order int NOT NULL CHECK (stage_order >= 1),
    min_score numeric(6, 2), -- khoảng điểm đầu vào phù hợp
    max_score numeric(6, 2),
    tuition numeric(14, 2) NOT NULL CHECK (tuition >= 0), -- học phí niêm yết
    total_sessions int NOT NULL CHECK (total_sessions > 0),
    pass_score numeric(5, 2) NOT NULL DEFAULT 50, -- điểm tổng kết tối thiểu để đạt
    is_active boolean NOT NULL DEFAULT true,
    UNIQUE (program_id, stage_order),
    CHECK (
        min_score IS NULL
        OR max_score IS NULL
        OR min_score <= max_score
    )
);

CREATE TABLE phong_hoc (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name text NOT NULL UNIQUE,
    capacity int NOT NULL CHECK (capacity > 0),
    is_active boolean NOT NULL DEFAULT true
);

CREATE TABLE lop_hoc ( -- lớp = một đợt mở của khóa
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    course_id bigint NOT NULL REFERENCES khoa_hoc (id),
    code text NOT NULL UNIQUE,
    teacher_id bigint NOT NULL REFERENCES nhan_vien (id), -- phải là employee_type = 'teacher' (kiểm tra ở ứng dụng)
    room_id bigint REFERENCES phong_hoc (id),
    start_date date NOT NULL,
    end_date date,
    weekdays smallint[] NOT NULL, -- 1 = thứ 2 ... 7 = chủ nhật, dùng để sinh buổi học
    start_time time NOT NULL,
    end_time time NOT NULL,
    min_size int NOT NULL DEFAULT 1 CHECK (min_size >= 1),
    max_size int NOT NULL CHECK (max_size >= 1),
    status text NOT NULL DEFAULT 'upcoming' CHECK (
        status IN (
            'upcoming',
            'ongoing',
            'grading',
            'finished',
            'cancelled'
        )
    ),
    online_link text, -- link lớp online / nhóm Zalo
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (min_size <= max_size),
    CHECK (start_time < end_time)
);

CREATE INDEX idx_lop_hoc_khoa_hoc ON lop_hoc (course_id);

CREATE INDEX idx_lop_hoc_giao_vien ON lop_hoc (teacher_id);

CREATE TABLE buoi_hoc ( -- buổi học
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    class_id bigint NOT NULL REFERENCES lop_hoc (id),
    session_no int NOT NULL,
    session_date date NOT NULL,
    start_time time NOT NULL,
    end_time time NOT NULL,
    room_id bigint REFERENCES phong_hoc (id),
    status text NOT NULL DEFAULT 'planned' CHECK (
        status IN (
            'planned',
            'taught',
            'cancelled',
            'makeup'
        )
    ),
    planned_teacher_id bigint NOT NULL REFERENCES nhan_vien (id),
    actual_teacher_id bigint REFERENCES nhan_vien (id), -- dạy thay: người dạy thật
    makeup_for_session_id bigint REFERENCES buoi_hoc (id), -- buổi bù trỏ về buổi nghỉ gốc
    cancel_reason text,
    cancel_by text CHECK (
        cancel_by IN (
            'teacher',
            'center',
            'holiday'
        )
    ),
    checkin_at timestamptz, -- giờ giáo viên mở điểm danh
    checkout_at timestamptz, -- giờ đóng điểm danh
    note text,
    UNIQUE (class_id, session_no),
    CHECK (start_time < end_time),
    CHECK (
        status <> 'makeup'
        OR makeup_for_session_id IS NOT NULL
    ),
    CHECK (
        status <> 'cancelled'
        OR cancel_reason IS NOT NULL
    ),
    -- chặn trùng phòng cùng khung giờ
    CONSTRAINT ex_buoi_hoc_phong EXCLUDE USING gist (
        room_id
        WITH
            =,
            tsrange (
                session_date + start_time,
                session_date + end_time
            )
        WITH
            &&
    )
    WHERE (
            status <> 'cancelled'
            AND room_id IS NOT NULL
        ),
        -- chặn trùng lịch giáo viên (người dạy thật nếu có, không thì người dự kiến)
        CONSTRAINT ex_buoi_hoc_giao_vien EXCLUDE USING gist (
            (
                COALESCE(
                    actual_teacher_id,
                    planned_teacher_id
                )
            )
            WITH
                =,
                tsrange (
                    session_date + start_time,
                    session_date + end_time
                )
            WITH
                &&
        )
    WHERE (status <> 'cancelled')
);

CREATE INDEX idx_buoi_hoc_lop_ngay ON buoi_hoc (class_id, session_date);

CREATE INDEX idx_buoi_hoc_gv_thuc_te ON buoi_hoc (
    actual_teacher_id,
    session_date
);


CREATE TABLE kiem_tra_dau_vao ( -- điểm đầu vào (làm bài ngoài hệ thống)
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    student_id bigint NOT NULL REFERENCES hoc_vien (id),
    test_date date NOT NULL,
    total_score numeric(6, 2) NOT NULL,
    listening numeric(6, 2),
    speaking numeric(6, 2),
    reading numeric(6, 2),
    writing numeric(6, 2),
    note text,
    entered_by bigint NOT NULL REFERENCES nhan_vien (id),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_kiem_tra_dau_vao_hoc_vien ON kiem_tra_dau_vao (student_id, test_date DESC);

CREATE TABLE dang_ky_lo_trinh ( -- ghi danh theo lộ trình
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    student_id bigint NOT NULL REFERENCES hoc_vien (id),
    program_id bigint NOT NULL REFERENCES lo_trinh (id),
    start_stage int NOT NULL CHECK (start_stage >= 1),
    end_stage int NOT NULL CHECK (end_stage >= 1),
    placement_test_id bigint REFERENCES kiem_tra_dau_vao (id),
    recommended_course_id bigint REFERENCES khoa_hoc (id), -- hệ thống gợi ý
    override_reason text, -- bắt buộc nếu Đào tạo xếp khác gợi ý
    status text NOT NULL DEFAULT 'in_progress' CHECK (
        status IN (
            'in_progress',
            'completed',
            'withdrawn',
            'dismissed'
        )
    ),
    registered_at timestamptz NOT NULL DEFAULT now(),
    created_by bigint NOT NULL REFERENCES nhan_vien (id),
    CHECK (start_stage <= end_stage)
);

CREATE INDEX idx_dang_ky_lo_trinh_hoc_vien ON dang_ky_lo_trinh (student_id);

CREATE TABLE ghi_danh ( -- ghi danh từng giai đoạn: đơn vị xử lý học phí, nợ, nghỉ
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    registration_id bigint NOT NULL REFERENCES dang_ky_lo_trinh (id),
    student_id bigint NOT NULL REFERENCES hoc_vien (id),
    course_id bigint NOT NULL REFERENCES khoa_hoc (id),
    class_id bigint REFERENCES lop_hoc (id), -- trống khi 'chờ xếp lớp'
    tuition_amount numeric(14, 2) CHECK (tuition_amount >= 0), -- chốt khi xếp lớp
    due_date date, -- = ngày khai giảng + 7 ngày; điền khi đã có lớp
    status text NOT NULL DEFAULT 'pending_class' CHECK (
        status IN (
            'pending_class',
            'studying',
            'completed',
            'withdrawn',
            'dismissed',
            'transferred',
            'cancelled'
        )
    ),
    dismiss_suggested boolean NOT NULL DEFAULT false, -- cờ đề nghị thôi học (qua nửa số buổi mà còn nợ)
    transferred_from_id bigint REFERENCES ghi_danh (id),
    tuition_adjust_reason text, -- lý do nếu Đào tạo chỉnh học phí chốt
    tuition_adjusted_by bigint REFERENCES nhan_vien (id),
    enrolled_at timestamptz NOT NULL DEFAULT now(),
    CHECK (
        class_id IS NULL
        OR (
            tuition_amount IS NOT NULL
            AND due_date IS NOT NULL
        )
    )
);

CREATE UNIQUE INDEX uq_ghi_danh_hoc_vien_lop ON ghi_danh (student_id, class_id)
WHERE
    class_id IS NOT NULL
    AND status NOT IN (
        'transferred',
        'cancelled',
        'withdrawn'
    );


CREATE UNIQUE INDEX uq_ghi_danh_giai_doan_hieu_luc ON ghi_danh (registration_id, course_id)
WHERE
    status IN ('pending_class', 'studying');

CREATE INDEX idx_ghi_danh_lop ON ghi_danh (class_id);

CREATE INDEX idx_ghi_danh_hoc_vien ON ghi_danh (student_id);

CREATE TABLE diem_danh (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    session_id bigint NOT NULL REFERENCES buoi_hoc (id),
    enrollment_id bigint NOT NULL REFERENCES ghi_danh (id),
    status text NOT NULL CHECK (
        status IN (
            'present',
            'absent',
            'late',
            'excused'
        )
    ),
    note text,
    recorded_by bigint NOT NULL REFERENCES nhan_vien (id),
    recorded_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (session_id, enrollment_id)
);

CREATE INDEX idx_diem_danh_ghi_danh ON diem_danh (enrollment_id);

CREATE TABLE ket_qua_hoc_tap ( -- kết quả học tập, giáo viên nhập tay
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    enrollment_id bigint NOT NULL UNIQUE REFERENCES ghi_danh (id),
    listening numeric(5, 2),
    speaking numeric(5, 2),
    reading numeric(5, 2),
    writing numeric(5, 2),
    total_score numeric(5, 2),
    is_passed boolean, -- = total_score >= khoa_hoc.pass_score
    comment text,
    entered_by bigint NOT NULL REFERENCES nhan_vien (id),
    entered_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    published_at timestamptz -- công bố khi lớp 'finished'
);

CREATE TABLE don_xin_nghi_hoc ( -- đơn xin nghỉ học
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    enrollment_id bigint NOT NULL REFERENCES ghi_danh (id),
    reason text NOT NULL,
    status text NOT NULL DEFAULT 'pending' CHECK (
        status IN (
            'pending',
            'approved',
            'rejected'
        )
    ),
    requested_at timestamptz NOT NULL DEFAULT now(),
    reviewed_by bigint REFERENCES nhan_vien (id),
    reviewed_at timestamptz,
    review_note text,
    -- số liệu chốt tại thời điểm duyệt
    sessions_held int, -- số buổi đã diễn ra (buổi vắng vẫn tính)
    payable_amount numeric(14, 2), -- học phí x (buổi đã học / tổng buổi)
    paid_amount numeric(14, 2),
    refund_amount numeric(14, 2) CHECK (
        refund_amount IS NULL
        OR refund_amount >= 0
    ),
    debt_amount numeric(14, 2) CHECK (
        debt_amount IS NULL
        OR debt_amount >= 0
    ), -- nợ cũ nếu đã đóng thiếu
    refund_due_date date -- = ngày duyệt + 15 ngày
);

CREATE INDEX idx_don_xin_nghi_ghi_danh ON don_xin_nghi_hoc (enrollment_id);

CREATE TABLE danh_gia ( -- phiếu đánh giá cuối khóa, ẩn danh với giáo viên
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    enrollment_id bigint NOT NULL UNIQUE REFERENCES ghi_danh (id), -- mỗi ghi danh một phiếu
    student_id bigint NOT NULL REFERENCES hoc_vien (id),
    class_id bigint NOT NULL REFERENCES lop_hoc (id),
    teacher_id bigint NOT NULL REFERENCES nhan_vien (id), -- chốt tại thời điểm gửi
    teacher_score smallint NOT NULL CHECK (
        teacher_score IN (10, 30, 50, 70, 90)
    ),
    course_score smallint NOT NULL CHECK (
        course_score IN (10, 30, 50, 70, 90)
    ),
    facility_score smallint NOT NULL CHECK (
        facility_score IN (10, 30, 50, 70, 90)
    ),
    comprehension_score smallint NOT NULL CHECK (
        comprehension_score IN (10, 30, 50, 70, 90)
    ),
    comment text,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_danh_gia_giao_vien ON danh_gia (teacher_id);

CREATE TABLE giao_dich_hoc_phi ( -- giao dịch tiền học phí, không xóa, sai thì điều chỉnh
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    enrollment_id bigint NOT NULL REFERENCES ghi_danh (id),
    payment_type text NOT NULL CHECK (
        payment_type IN (
            'collect',
            'refund',
            'adjustment',
            'transfer_out',
            'transfer_in'
        )
    ),
    method text NOT NULL CHECK (method IN ('cash', 'online')),
    status text NOT NULL DEFAULT 'success' CHECK (
        status IN (
            'pending',
            'success',
            'failed',
            'expired'
        )
    ),
    amount numeric(14, 2) NOT NULL CHECK (amount > 0),
    txn_ref text UNIQUE, -- mã giao dịch của hệ thống gửi cổng (chống ghi trùng)
    gateway_txn_no text, -- mã giao dịch phía cổng thanh toán
    receipt_no text, -- số biên lai tiền mặt
    related_payment_id bigint REFERENCES giao_dich_hoc_phi (id), -- bút toán điều chỉnh / cặp chuyển lớp
    recorded_by bigint REFERENCES nhan_vien (id), -- người thu (trống nếu online)
    paid_at timestamptz,
    gateway_response jsonb, -- dữ liệu IPN thô để đối soát
    note text,
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (
        method <> 'cash'
        OR (
            recorded_by IS NOT NULL
            AND receipt_no IS NOT NULL
        )
    )
);

CREATE INDEX idx_giao_dich_ghi_danh ON giao_dich_hoc_phi (enrollment_id);

CREATE UNIQUE INDEX uq_giao_dich_ma_cong ON giao_dich_hoc_phi (gateway_txn_no)
WHERE
    gateway_txn_no IS NOT NULL;

CREATE TABLE luong ( -- lương kỳ, ứng, quyết toán nghỉ việc, thu hồi nợ, điều chỉnh
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    employee_id bigint NOT NULL REFERENCES nhan_vien (id),
    period date NOT NULL, -- ngày đầu tháng của kỳ lương
    salary_type text NOT NULL CHECK (
        salary_type IN (
            'period',
            'advance',
            'settlement',
            'debt_recovery',
            'adjustment'
        )
    ),
    work_days numeric(5, 1), -- số công căn cứ (nhân viên)
    standard_days numeric(5, 1), -- số công chuẩn của tháng
    work_hours numeric(7, 2), -- số giờ dạy căn cứ (giáo viên)
    unit_rate numeric(14, 2), -- đơn giá giờ (giáo viên) hoặc lương cơ bản (nhân viên)
    gross_amount numeric(14, 2) NOT NULL DEFAULT 0,
    advance_deducted numeric(14, 2) NOT NULL DEFAULT 0, -- ứng chưa khấu trừ được trừ trong kỳ này
    adjust_amount numeric(14, 2) NOT NULL DEFAULT 0,
    net_amount numeric(14, 2) NOT NULL DEFAULT 0,
    status text NOT NULL DEFAULT 'calculated' CHECK (
        status IN (
            'requested',
            'approved',
            'rejected',
            'calculated',
            'paid',
            'cancelled'
        )
    ),
    requested_at timestamptz, -- dùng cho yêu cầu ứng lương
    approved_by bigint REFERENCES nhan_vien (id),
    paid_by bigint REFERENCES nhan_vien (id),
    paid_at timestamptz,
    is_locked boolean NOT NULL DEFAULT false, -- chốt kỳ: Admin mở khóa kèm lý do
    note text,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_luong_nhan_vien_ky ON luong (employee_id, period);

CREATE TABLE don_nghi_phep ( -- nghỉ phép và đơn thôi việc
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    employee_id bigint NOT NULL REFERENCES nhan_vien (id),
    leave_type text NOT NULL CHECK (
        leave_type IN (
            'paid',
            'unpaid',
            'sick',
            'resignation'
        )
    ),
    from_date date NOT NULL, -- với 'resignation' là ngày hiệu lực
    to_date date NOT NULL,
    reason text,
    status text NOT NULL DEFAULT 'pending' CHECK (
        status IN (
            'pending',
            'approved',
            'rejected',
            'cancelled'
        )
    ),
    reviewed_by bigint REFERENCES nhan_vien (id), -- Nhân sự duyệt; Admin duyệt đơn của Nhân sự
    reviewed_at timestamptz,
    review_note text,
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (from_date <= to_date)
);

CREATE INDEX idx_don_nghi_phep_nhan_vien ON don_nghi_phep (employee_id, from_date);

CREATE TABLE cham_cong ( -- chấm công nhân viên theo ngày (giáo viên tính theo buổi dạy)
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    employee_id bigint NOT NULL REFERENCES nhan_vien (id),
    work_date date NOT NULL,
    check_in timestamptz, -- giờ máy chủ, không do người dùng nhập
    check_out timestamptz,
    status text NOT NULL CHECK (
        status IN (
            'full',
            'half',
            'late',
            'paid_leave',
            'unpaid_leave',
            'holiday',
            'absent',
            'missing_checkout'
        )
    ),
    work_units numeric(3, 1) NOT NULL DEFAULT 0 CHECK (work_units BETWEEN 0 AND 1),
    source text NOT NULL DEFAULT 'self' CHECK (
        source IN (
            'self',
            'adjusted',
            'leave',
            'system'
        )
    ),
    adjusted_by bigint REFERENCES nhan_vien (id), -- Nhân sự sửa; Admin sửa công của Nhân sự
    adjust_reason text,
    is_locked boolean NOT NULL DEFAULT false,
    note text,
    UNIQUE (employee_id, work_date),
    CHECK (
        source <> 'adjusted'
        OR (
            adjusted_by IS NOT NULL
            AND adjust_reason IS NOT NULL
        )
    ),
    CHECK (
        check_out IS NULL
        OR check_in IS NULL
        OR check_out >= check_in
    )
);


CREATE TABLE cau_hinh_he_thong (
    config_key text PRIMARY KEY,
    config_value text NOT NULL,
    value_type text NOT NULL DEFAULT 'text' CHECK (
        value_type IN (
            'text',
            'number',
            'boolean',
            'json'
        )
    ),
    description text,
    updated_by bigint REFERENCES nhan_vien (id),
    updated_at timestamptz NOT NULL DEFAULT now()
);


INSERT INTO
    cau_hinh_he_thong (
        config_key,
        config_value,
        value_type,
        description
    )
VALUES (
        'base_hourly_rate',
        '0',
        'number',
        'Mức cơ sở theo quy định để tính đơn giá giờ giáo viên (tự nhập)'
    ),
    (
        'advance_max_percent',
        '35',
        'number',
        'Tỷ lệ ứng lương tối đa (%) trên phần lương đã làm ra trong kỳ'
    ),
    (
        'advance_max_per_month',
        '1',
        'number',
        'Số lần ứng tối đa mỗi tháng'
    ),
    (
        'tuition_due_days',
        '7',
        'number',
        'Hạn đóng = ngày khai giảng + N ngày'
    ),
    (
        'dismiss_flag_session_ratio',
        '0.5',
        'number',
        'Gắn cờ đề nghị thôi học khi lớp qua tỷ lệ buổi này mà còn nợ'
    ),
    (
        'refund_days',
        '15',
        'number',
        'Số ngày hoàn tiền sau khi duyệt đơn nghỉ'
    ),
    (
        'placement_valid_months',
        '6',
        'number',
        'Hạn dùng điểm đầu vào (tháng)'
    ),
    (
        'annual_paid_leave_days',
        '12',
        'number',
        'Số ngày phép có lương mỗi năm (tự quy định)'
    ),
    (
        'standard_work_days',
        '26',
        'number',
        'Số công chuẩn mỗi tháng (tự quy định)'
    ),
    (
        'work_start_time',
        '08:00',
        'text',
        'Giờ vào ca quy định'
    ),
    (
        'late_grace_minutes',
        '15',
        'number',
        'Ngưỡng cho phép đi trễ (phút)'
    ),
    (
        'half_day_max_hours',
        '4',
        'number',
        'Làm dưới ngưỡng giờ này tính nửa công'
    ),
    (
        'settlement_days',
        '14',
        'number',
        'Hạn chi quyết toán sau khi nghỉ việc (tự tra quy định)'
    ),
    (
        'resign_notice_days',
        '30',
        'number',
        'Số ngày báo trước khi nghỉ việc (tự tra quy định)'
    ),
    (
        'makeup_deadline_days',
        '14',
        'number',
        'Hạn dạy bù sau buổi nghỉ do giáo viên'
    ),
    (
        'attendance_edit_hours',
        '48',
        'number',
        'Sửa điểm danh sau số giờ này cần Đào tạo duyệt'
    ),
    (
        'evaluation_min_count',
        '5',
        'number',
        'Số phiếu tối thiểu để đưa giáo viên vào K-means'
    ),
    (
        'holidays',
        '[]',
        'json',
        'Danh sách ngày lễ dạng ["2026-09-02", ...]'
    ),
    (
        'timekeeping_allowed_ips',
        '[]',
        'json',
        'Giới hạn IP chấm công, rỗng = không giới hạn'
    );

CREATE TABLE phan_nhom_giao_vien ( -- mỗi dòng = một giáo viên trong một lần chạy K-means
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    run_id uuid NOT NULL, -- gom các dòng cùng một lần chạy
    run_at timestamptz NOT NULL DEFAULT now(),
    run_by bigint REFERENCES nhan_vien (id),
    k int NOT NULL CHECK (k >= 2),
    teacher_id bigint NOT NULL REFERENCES nhan_vien (id),
    pass_rate numeric(5, 2) NOT NULL, -- tỷ lệ đạt (%)
    absence_rate numeric(5, 2) NOT NULL, -- tỷ lệ vắng (%)
    avg_teacher_score numeric(5, 2) NOT NULL, -- điểm đánh giá giảng viên trung bình (10-90)
    evaluation_count int NOT NULL,
    cluster_no int NOT NULL,
    cluster_label text, -- nhãn do người xem gán sau khi nhìn tâm cụm
    UNIQUE (run_id, teacher_id)
);

CREATE INDEX idx_phan_nhom_lan_chay ON phan_nhom_giao_vien (run_id);



CREATE TABLE nhat_ky_thao_tac (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    actor_user_id bigint REFERENCES tai_khoan (id),
    action text NOT NULL, -- vd: UPDATE_RESULT, ADJUST_PAYMENT, UNLOCK_PAYROLL
    entity_type text NOT NULL,
    entity_id bigint,
    old_value jsonb,
    new_value jsonb,
    reason text, -- bắt buộc với thao tác ghi đè của Admin
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_nhat_ky_doi_tuong ON nhat_ky_thao_tac (entity_type, entity_id);

